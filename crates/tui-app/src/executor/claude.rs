use anyhow::Result;
use async_trait::async_trait;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;
use tokio::process::{Command as TokioCommand, Child};
use tokio::io::{AsyncBufReadExt, BufReader};

use super::traits::{ExecutorSession, ExecutorConfig, ExecutorType, ExecutorOutput};

/// Claude Code executor implementation
pub struct ClaudeExecutor {
    child: Child,
    stdout_reader: tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    stderr_reader: tokio::io::Lines<BufReader<tokio::process::ChildStderr>>,
    config: ExecutorConfig,
}

impl ClaudeExecutor {
    /// Expand tilde in path to home directory
    fn expand_tilde(path: &PathBuf) -> PathBuf {
        if let Some(path_str) = path.to_str() {
            if path_str.starts_with("~/") {
                if let Some(home) = std::env::var_os("HOME") {
                    let mut expanded = PathBuf::from(home);
                    expanded.push(&path_str[2..]);
                    return expanded;
                }
            }
        }
        path.clone()
    }

    /// Ensure directory exists
    fn ensure_dir(path: &PathBuf) -> Result<PathBuf> {
        let expanded = Self::expand_tilde(path);
        if !expanded.exists() {
            std::fs::create_dir_all(&expanded)?;
        }
        Ok(expanded)
    }
}

#[async_trait]
impl ExecutorSession for ClaudeExecutor {
    fn executor_type(&self) -> ExecutorType {
        ExecutorType::Claude
    }
    
    async fn launch(prompt: &str, config: ExecutorConfig) -> Result<Box<dyn ExecutorSession>> {
        // Ensure working directory exists
        let working_dir = Self::ensure_dir(&config.working_dir)?;
        
        // Build the Claude command
        let mut cmd = TokioCommand::new("claude");
        
        // Core arguments
        cmd.arg("-p")
           .arg(prompt);
        
        // Add permission skip if configured
        if config.skip_permissions {
            cmd.arg("--dangerously-skip-permissions");
        }
        
        // Add working directory
        cmd.arg("--add-dir")
           .arg(&working_dir)
           .current_dir(&working_dir);
        
        // Add custom flags
        for flag in &config.custom_flags {
            cmd.arg(flag);
        }
        
        // Set up pipes
        cmd.stdout(Stdio::piped())
           .stderr(Stdio::piped());
        
        // Spawn the process
        let mut child = cmd.spawn()?;
        
        // Get handles to stdout and stderr
        let stdout = child.stdout.take()
            .ok_or_else(|| anyhow::anyhow!("Failed to capture stdout"))?;
        let stderr = child.stderr.take()
            .ok_or_else(|| anyhow::anyhow!("Failed to capture stderr"))?;
        
        Ok(Box::new(ClaudeExecutor {
            child,
            stdout_reader: BufReader::new(stdout).lines(),
            stderr_reader: BufReader::new(stderr).lines(),
            config,
        }))
    }
    
    async fn read_output(&mut self) -> Result<Option<ExecutorOutput>> {
        // Try to read from stdout first
        match tokio::time::timeout(Duration::from_millis(10), self.stdout_reader.next_line()).await {
            Ok(Ok(Some(line))) if !line.trim().is_empty() => {
                return Ok(Some(ExecutorOutput::Stdout(line)));
            }
            _ => {}
        }
        
        // Then try stderr
        match tokio::time::timeout(Duration::from_millis(10), self.stderr_reader.next_line()).await {
            Ok(Ok(Some(line))) if !line.trim().is_empty() => {
                return Ok(Some(ExecutorOutput::Stderr(line)));
            }
            _ => {}
        }
        
        Ok(None)
    }
    
    fn is_running(&mut self) -> bool {
        self.child.try_wait().ok().flatten().is_none()
    }
    
    async fn terminate(&mut self) -> Result<()> {
        self.child.kill().await?;
        Ok(())
    }
    
    fn get_metadata(&self) -> Option<serde_json::Value> {
        Some(serde_json::json!({
            "executor": "claude",
            "working_dir": self.config.working_dir.to_string_lossy(),
            "skip_permissions": self.config.skip_permissions,
        }))
    }
}

/// Ensure Claude process is killed when executor is dropped
impl Drop for ClaudeExecutor {
    fn drop(&mut self) {
        // Try to kill the child process
        if let Ok(Some(_)) = self.child.try_wait() {
            // Process already exited
            return;
        }
        
        // Force kill if still running
        let _ = self.child.start_kill();
    }
}