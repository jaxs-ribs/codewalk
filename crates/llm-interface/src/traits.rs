use anyhow::Result;
use async_trait::async_trait;
use crate::types::CommandPlan;

#[async_trait]
pub trait LLMProvider: Send + Sync {
    /// Initialize the provider with configuration
    async fn initialize(&mut self, config: serde_json::Value) -> Result<()>;
    
    /// Convert text to a command plan
    async fn text_to_plan(&self, text: &str) -> Result<String>;
    
    /// Get the provider name
    fn name(&self) -> &str;
    
    /// Check if ready
    fn is_ready(&self) -> bool;
}

pub trait PlanExtractor: Send + Sync {
    /// Extract a structured command plan from JSON string
    fn extract_plan(&self, json_str: &str) -> Result<CommandPlan>;
    
    /// Extract just the first command from a plan
    fn extract_first_command(&self, json_str: &str) -> Result<Option<String>>;
}