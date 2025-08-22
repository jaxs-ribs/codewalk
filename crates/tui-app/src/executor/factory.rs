use anyhow::Result;
use super::traits::{ExecutorSession, ExecutorConfig, ExecutorType};
use super::claude::ClaudeExecutor;

/// Factory for creating executor sessions
pub struct ExecutorFactory;

impl ExecutorFactory {
    /// Create a new executor session of the specified type
    pub async fn create(
        executor_type: ExecutorType,
        prompt: &str,
        config: Option<ExecutorConfig>,
    ) -> Result<Box<dyn ExecutorSession>> {
        let config = config.unwrap_or_default();
        
        match executor_type {
            ExecutorType::Claude => {
                ClaudeExecutor::launch(prompt, config).await
            }
            ExecutorType::Devin => {
                Err(anyhow::anyhow!("Devin executor not yet implemented"))
            }
            ExecutorType::Codex => {
                Err(anyhow::anyhow!("Codex executor not yet implemented"))
            }
            ExecutorType::Custom(name) => {
                Err(anyhow::anyhow!("Custom executor '{}' not implemented", name))
            }
        }
    }
    
    /// Get the default executor type
    pub fn default_executor() -> ExecutorType {
        ExecutorType::Claude
    }
    
    /// Check if an executor type is available
    pub fn is_available(executor_type: &ExecutorType) -> bool {
        match executor_type {
            ExecutorType::Claude => {
                // Check if claude command exists
                std::process::Command::new("which")
                    .arg("claude")
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
            }
            _ => false,
        }
    }
    
    /// Get list of available executors
    pub fn available_executors() -> Vec<ExecutorType> {
        vec![
            ExecutorType::Claude,
            // Add more as they become available
        ]
        .into_iter()
        .filter(|e| Self::is_available(e))
        .collect()
    }
}