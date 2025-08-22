use anyhow::Result;
use async_trait::async_trait;
use std::path::PathBuf;

/// Type of executor backend
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum ExecutorType {
    Claude,
    Devin,      // Future
    Codex,      // Future
    Custom(String),
}

impl ExecutorType {
    /// Get human-readable name
    pub fn name(&self) -> &str {
        match self {
            ExecutorType::Claude => "Claude",
            ExecutorType::Devin => "Devin",
            ExecutorType::Codex => "Codex",
            ExecutorType::Custom(name) => name,
        }
    }
}

/// Configuration for an executor session
#[derive(Debug, Clone)]
pub struct ExecutorConfig {
    /// Working directory for the executor
    pub working_dir: PathBuf,
    /// Optional log directory
    #[allow(dead_code)]
    pub log_dir: Option<PathBuf>,
    /// Whether to skip permission prompts
    pub skip_permissions: bool,
    /// Custom flags for the executor
    pub custom_flags: Vec<String>,
}

impl Default for ExecutorConfig {
    fn default() -> Self {
        Self {
            working_dir: PathBuf::from("~/Documents/walking-projects/first"),
            log_dir: Some(PathBuf::from("~/Documents/walking-projects/logs")),
            skip_permissions: true,
            custom_flags: Vec::new(),
        }
    }
}

/// Output from an executor
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum ExecutorOutput {
    Stdout(String),
    Stderr(String),
    Status(String),
    Progress(f32, String), // Progress percentage and message
}

/// Trait for code executor sessions (Claude, Devin, etc.)
#[async_trait]
pub trait ExecutorSession: Send {
    /// Get the executor type
    #[allow(dead_code)]
    fn executor_type(&self) -> ExecutorType;
    
    /// Launch the executor with a prompt
    async fn launch(prompt: &str, config: ExecutorConfig) -> Result<Box<dyn ExecutorSession>>
    where
        Self: Sized;
    
    /// Read next output from the executor (non-blocking)
    async fn read_output(&mut self) -> Result<Option<ExecutorOutput>>;
    
    /// Check if the executor is still running
    fn is_running(&mut self) -> bool;
    
    /// Send input to the executor (if supported)
    #[allow(dead_code)]
    async fn send_input(&mut self, _input: &str) -> Result<()> {
        Err(anyhow::anyhow!("Input not supported by this executor"))
    }
    
    /// Terminate the executor session
    async fn terminate(&mut self) -> Result<()>;
    
    /// Get session metadata
    #[allow(dead_code)]
    fn get_metadata(&self) -> Option<serde_json::Value> {
        None
    }
}