use anyhow::Result;
use tokio::sync::mpsc;
use std::path::Path;

use crate::executor::{ExecutorFactory, ExecutorSession, ExecutorType, ExecutorConfig, ExecutorOutput};
use crate::logs::{ParsedLogLine, spawn_log_monitor};

/// Frontend‑agnostic control center that manages editor sessions
pub struct ControlCenter {
    pub executor: ExecutorType,
    pub session: Option<Box<dyn ExecutorSession>>,
    pub log_rx: Option<mpsc::Receiver<ParsedLogLine>>,
}

impl ControlCenter {
    pub fn new() -> Self {
        Self {
            executor: ExecutorFactory::default_executor(),
            session: None,
            log_rx: None,
        }
    }

    /// Launch an editor session with a prompt and optional config
    pub async fn launch(&mut self, prompt: &str, config: Option<ExecutorConfig>) -> Result<()> {
        let session = ExecutorFactory::create(self.executor.clone(), prompt, config.clone()).await?;
        self.session = Some(session);

        // Attach logging if requested
        if let Some(cfg) = config {
            let rx = spawn_log_monitor(Some(&cfg.working_dir));
            self.log_rx = Some(rx);
        }
        Ok(())
    }
    
    /// Launch an editor session with resume flag
    pub async fn launch_with_resume(&mut self, prompt: &str, resume_session_id: &str, config: Option<ExecutorConfig>) -> Result<()> {
        let session = ExecutorFactory::create_with_resume(self.executor.clone(), prompt, resume_session_id, config.clone()).await?;
        self.session = Some(session);

        // Attach logging if requested
        if let Some(cfg) = config {
            let rx = spawn_log_monitor(Some(&cfg.working_dir));
            self.log_rx = Some(rx);
        }
        Ok(())
    }

    /// Attach a log monitor for a working directory (without launching)
    pub fn attach_logs(&mut self, working_dir: &Path) {
        let rx = spawn_log_monitor(Some(working_dir));
        self.log_rx = Some(rx);
    }

    /// Poll logs non‑blocking; returns up to `limit` items if available
    pub async fn poll_logs(&mut self, limit: usize) -> Vec<ParsedLogLine> {
        let mut out = Vec::new();
        if let Some(rx) = &mut self.log_rx {
            for _ in 0..limit.max(1) {
                match rx.try_recv() {
                    Ok(item) => out.push(item),
                    Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                    Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                        self.log_rx = None;
                        break;
                    }
                }
            }
        }
        out
    }

    /// Poll executor stdout/stderr non‑blocking; returns up to `limit` items
    pub async fn poll_executor_output(&mut self, limit: usize) -> Vec<ExecutorOutput> {
        let mut outputs = Vec::new();
        if let Some(session) = &mut self.session {
            for _ in 0..limit.max(1) {
                match session.read_output().await {
                    Ok(Some(output)) => outputs.push(output),
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
        }
        outputs
    }

    /// Check if a session is running
    pub fn is_running(&mut self) -> bool {
        if let Some(session) = &mut self.session {
            session.is_running()
        } else {
            false
        }
    }

    /// Terminate the running session if any
    pub async fn terminate(&mut self) -> Result<()> {
        if let Some(mut s) = self.session.take() {
            s.terminate().await?;
        }
        Ok(())
    }
}
