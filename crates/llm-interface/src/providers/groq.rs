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
        // Use Kimi K2 for better performance and prompt caching
        let client = llm_client::Client::from_env_groq("moonshotai/kimi-k2-instruct")?;
        self.client = Some(client);
        self.ready = true;
        Ok(())
    }
    
    async fn text_to_plan(&self, text: &str) -> Result<String> {
        let client = self.client.as_ref()
            .ok_or_else(|| anyhow::anyhow!("GroqProvider not initialized"))?;
        
        // STABLE SYSTEM PROMPT - Keep exactly the same for prompt caching
        // This prefix will be cached across all requests, saving 50% on tokens
        let system_prompt = r#"You are a voice command router for a development assistant.

TASK: Determine if the user wants to start a coding/development task with Claude Code.

CLASSIFICATION RULES:
- launch_claude: Any request involving code, programming, debugging, or software development
- cannot_parse: Non-technical requests, unclear speech, or unrelated topics

CODING TASK PATTERNS:
- Fix/debug/resolve [technical issue]
- Write/create/build [code/script/app]
- Implement/add [feature/functionality]
- Refactor/optimize/improve [code]
- Help with [programming task]
- Analyze/review [code]
- Setup/configure [technical system]

NON-CODING PATTERNS:
- Weather/news/entertainment requests
- Greetings or social conversation
- Unclear or garbled speech
- Non-technical questions

OUTPUT FORMAT (JSON only):
{
  "action": "launch_claude" or "cannot_parse",
  "prompt": "exact user request if launch_claude, null otherwise",
  "reason": "brief explanation if cannot_parse, null otherwise",
  "confidence": 0.0 to 1.0
}

IMPORTANT: Preserve the user's exact words in the prompt field."#;

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