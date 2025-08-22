use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    /// Whether to require confirmation before launching executor
    pub require_executor_confirmation: bool,
    
    /// Default executor type
    pub default_executor: String,
    
    /// Working directory for executors
    pub executor_working_dir: String,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            require_executor_confirmation: true,  // Safe by default
            default_executor: "Claude".to_string(),
            executor_working_dir: "~/Documents/walking-projects/first".to_string(),
        }
    }
}

impl AppSettings {
    /// Load settings from config file or use defaults
    pub fn load() -> Self {
        // For now, just use defaults
        // TODO: Load from ~/.codewalk/settings.json
        Self::default()
    }
    
    /// Save settings to config file
    #[allow(dead_code)]
    pub fn save(&self) -> anyhow::Result<()> {
        // TODO: Save to ~/.codewalk/settings.json
        Ok(())
    }
}