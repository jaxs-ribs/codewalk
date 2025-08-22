use anyhow::Result;
use std::process::Stdio;
use std::path::PathBuf;
use tokio::process::{Command as TokioCommand, Child};
use tokio::io::{AsyncBufReadExt, BufReader};
use std::time::Duration;

// Constants for Claude Code configuration
pub const PROJECT_DIR: &str = "~/Documents/walking-projects/first";
pub const LOGS_DIR: &str = "~/Documents/walking-projects/logs";

/// Expand tilde in path to home directory
fn expand_tilde(path: &str) -> PathBuf {
    if path.starts_with("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            let mut expanded = PathBuf::from(home);
            expanded.push(&path[2..]);
            return expanded;
        }
    }
    PathBuf::from(path)
}

/// Ensure project directory exists
pub fn ensure_project_dir() -> Result<PathBuf> {
    let project_path = expand_tilde(PROJECT_DIR);
    if !project_path.exists() {
        std::fs::create_dir_all(&project_path)?;
    }
    Ok(project_path)
}

/// Launch Claude Code session in headless mode
pub async fn launch_claude_session(prompt: &str) -> Result<ClaudeSession> {
    // Ensure project directory exists
    let project_dir = ensure_project_dir()?;
    
    // Build the Claude command
    // Using -p for headless/print mode
    // Using --dangerously-skip-permissions to avoid blocking on permission prompts
    let mut cmd = TokioCommand::new("claude");
    cmd.arg("-p")
       .arg(prompt)
       .arg("--dangerously-skip-permissions")
       .arg("--add-dir")
       .arg(&project_dir)
       .current_dir(&project_dir)
       .stdout(Stdio::piped())
       .stderr(Stdio::piped());
    
    // Spawn the process
    let mut child = cmd.spawn()?;
    
    // Get handles to stdout and stderr
    let stdout = child.stdout.take()
        .ok_or_else(|| anyhow::anyhow!("Failed to capture stdout"))?;
    let stderr = child.stderr.take()
        .ok_or_else(|| anyhow::anyhow!("Failed to capture stderr"))?;
    
    Ok(ClaudeSession {
        child,
        stdout_reader: BufReader::new(stdout).lines(),
        stderr_reader: BufReader::new(stderr).lines(),
    })
}

/// Represents an active Claude Code session
pub struct ClaudeSession {
    child: Child,
    stdout_reader: tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    stderr_reader: tokio::io::Lines<BufReader<tokio::process::ChildStderr>>,
}

/// Ensure Claude process is killed when session is dropped
impl Drop for ClaudeSession {
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

impl ClaudeSession {
    /// Read next line from stdout (non-blocking with timeout)
    pub async fn read_stdout_line(&mut self) -> Result<Option<String>> {
        match tokio::time::timeout(Duration::from_millis(10), self.stdout_reader.next_line()).await {
            Ok(Ok(Some(line))) => Ok(Some(line)),
            Ok(Ok(None)) => Ok(None),
            Ok(Err(e)) => Err(e.into()),
            Err(_) => Ok(None), // Timeout - no data available
        }
    }
    
    /// Read next line from stderr (non-blocking with timeout)
    pub async fn read_stderr_line(&mut self) -> Result<Option<String>> {
        match tokio::time::timeout(Duration::from_millis(10), self.stderr_reader.next_line()).await {
            Ok(Ok(Some(line))) => Ok(Some(line)),
            Ok(Ok(None)) => Ok(None),
            Ok(Err(e)) => Err(e.into()),
            Err(_) => Ok(None), // Timeout - no data available
        }
    }
    
    /// Check if the process is still running
    pub fn is_running(&mut self) -> bool {
        self.child.try_wait().ok().flatten().is_none()
    }
    
    /// Terminate the Claude session
    pub async fn terminate(&mut self) -> Result<()> {
        self.child.kill().await?;
        Ok(())
    }
}

/// Launch Claude with streaming JSON output for better parsing
pub async fn launch_claude_json(prompt: &str) -> Result<ClaudeSession> {
    let project_dir = ensure_project_dir()?;
    
    let mut cmd = TokioCommand::new("claude");
    cmd.arg("-p")
       .arg(prompt)
       .arg("--dangerously-skip-permissions")
       .arg("--output-format")
       .arg("stream-json")
       .arg("--add-dir")
       .arg(&project_dir)
       .current_dir(&project_dir)
       .stdout(Stdio::piped())
       .stderr(Stdio::piped());
    
    let mut child = cmd.spawn()?;
    
    let stdout = child.stdout.take()
        .ok_or_else(|| anyhow::anyhow!("Failed to capture stdout"))?;
    let stderr = child.stderr.take()
        .ok_or_else(|| anyhow::anyhow!("Failed to capture stderr"))?;
    
    Ok(ClaudeSession {
        child,
        stdout_reader: BufReader::new(stdout).lines(),
        stderr_reader: BufReader::new(stderr).lines(),
    })
}