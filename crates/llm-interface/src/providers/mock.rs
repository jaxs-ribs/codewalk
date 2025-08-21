use anyhow::Result;
use async_trait::async_trait;
use crate::traits::LLMProvider;

/// Mock provider for testing
pub struct MockProvider {
    ready: bool,
}

impl MockProvider {
    pub fn new() -> Self {
        Self { ready: false }
    }
}

#[async_trait]
impl LLMProvider for MockProvider {
    async fn initialize(&mut self, _config: serde_json::Value) -> Result<()> {
        self.ready = true;
        Ok(())
    }
    
    async fn text_to_plan(&self, text: &str) -> Result<String> {
        // Return a mock plan based on the input
        if text.contains("bandit") {
            Ok(r#"{"status":"ok","confidence":{"score":0.8,"label":"high"},"plan":{"cwd":"~","explanation":"SSH then print README","steps":[{"cmd":"ssh bandit0@bandit.labs.overthewire.org -p 2220"},{"cmd":"cat readme"}]}}"#.to_string())
        } else {
            Ok(format!(
                r#"{{"status":"ok","plan":{{"steps":[{{"cmd":"echo 'Simulated: {}'"}}]}}}}"#,
                text
            ))
        }
    }
    
    fn name(&self) -> &str {
        "mock"
    }
    
    fn is_ready(&self) -> bool {
        self.ready
    }
}