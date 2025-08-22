use anyhow::Result;
use async_trait::async_trait;
use crate::traits::LLMProvider;
use crate::types::RouterResponse;

pub struct GroqProvider {
    client: Option<llm_client::Client>,
    ready: bool,
}

impl GroqProvider {
    pub fn new() -> Self {
        Self {
            client: None,
            ready: false,
        }
    }
}

#[async_trait]
impl LLMProvider for GroqProvider {
    async fn initialize(&mut self, _config: serde_json::Value) -> Result<()> {
        // Use llm_client with env-based config
        let client = llm_client::Client::from_env_groq("llama-3.1-8b-instant")?;
        self.client = Some(client);
        self.ready = true;
        Ok(())
    }
    
    async fn text_to_plan(&self, text: &str) -> Result<String> {
        let client = self.client.as_ref()
            .ok_or_else(|| anyhow::anyhow!("GroqProvider not initialized"))?;
        
        // System prompt for routing voice commands
        let system_prompt = r#"You are a voice command router for a development assistant.
Analyze the user's request and determine if they want to:
1. Start a coding/development task with Claude Code (launch_claude)
2. Something else or unclear (cannot_parse)

Examples of coding tasks:
- "Fix the bug in authentication"
- "Write a Python script to process CSV files"
- "Help me refactor this component"
- "Create a REST API"
- "Debug this error"
- "Implement a new feature"

Examples of non-coding tasks:
- "What's the weather?"
- "Play music"
- "Hello"
- Unclear/garbled speech

Respond with JSON only:
{
  "action": "launch_claude" or "cannot_parse",
  "prompt": "the exact user request if launch_claude, null otherwise",
  "reason": "explanation if cannot_parse, null otherwise",
  "confidence": 0.0 to 1.0
}"#;

        let messages = vec![
            llm_client::ChatMessage {
                role: llm_client::Role::System,
                content: system_prompt.to_string(),
            },
            llm_client::ChatMessage {
                role: llm_client::Role::User,
                content: format!("Voice command: \"{}\"", text),
            },
        ];
        
        let options = llm_client::ChatOptions {
            temperature: Some(0.1),
            json_object: true,
        };
        
        let response = client.chat(&messages, options).await?;
        
        // Validate it's proper JSON
        let parsed: RouterResponse = serde_json::from_str(&response)?;
        
        // Re-serialize to ensure consistent format
        Ok(serde_json::to_string(&parsed)?)
    }
    
    fn name(&self) -> &str {
        "GroqProvider"
    }
    
    fn is_ready(&self) -> bool {
        self.ready
    }
}