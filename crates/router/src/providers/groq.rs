use anyhow::Result;
use async_trait::async_trait;
use crate::traits::LLMProvider;
use crate::types::RouterResponse;
use crate::memory::ConversationMemory;

pub struct GroqProvider {
    client: Option<llm::Client>,
    ready: bool,
    model: String,
    memory: ConversationMemory,
}

impl GroqProvider {
    pub fn new() -> Self {
        // Check environment variable for model selection
        // Default to llama-3.1-8b-instant when K2 is over capacity
        let model = std::env::var("GROQ_MODEL")
            .unwrap_or_else(|_| "llama-3.1-8b-instant".to_string());
        
        Self {
            client: None,
            ready: false,
            model,
            memory: ConversationMemory::new(),
        }
    }
}

#[async_trait]
impl LLMProvider for GroqProvider {
    async fn initialize(&mut self, _config: serde_json::Value) -> Result<()> {
        // Use the model from environment or default
        let client = llm::Client::from_env_groq(&self.model)?;
        self.client = Some(client);
        self.ready = true;
        
        // Log which model we're using
        eprintln!("GroqProvider initialized with model: {}", self.model);
        Ok(())
    }
    
    async fn text_to_plan(&mut self, text: &str) -> Result<String> {
        let client = self.client.as_ref()
            .ok_or_else(|| anyhow::anyhow!("GroqProvider not initialized"))?;
        
        // Build context from memory
        let history_context = self.memory.get_context_for_llm();
        
        // Use different prompts based on model
        let base_system_prompt = if self.model.contains("kimi") {
            // STABLE SYSTEM PROMPT FOR KIMI K2 - Keep exactly the same for prompt caching
            // This prefix will be cached across all requests, saving 50% on tokens
            r#"You are a voice command router for a development assistant.

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

IMPORTANT: Preserve the user's exact words in the prompt field."#
        } else {
            // Shorter prompt for Llama models (no prompt caching)
            r#"You are a voice command router. Determine the user's intent.

CONTEXT MARKERS:
- [ACTIVE_SESSION: X] means an executor session is running
- [NO_ACTIVE_SESSION] means no session is active

ROUTING RULES:
When ACTIVE_SESSION:
- Questions about progress/status/what's happening → action: "cannot_parse", reason: "query status"
- New coding requests → action: "launch_claude"
- Other → action: "cannot_parse"

When NO_ACTIVE_SESSION:
- Coding tasks → action: "launch_claude"  
- Non-technical → action: "cannot_parse"

IMPORTANT: Always use "cannot_parse" as the action when returning "query status" as the reason.
Return JSON: {"action": "launch_claude" or "cannot_parse", "prompt": "user request or null", "reason": "explanation or null", "confidence": 0.0-1.0}"#
        };
        
        // Combine base prompt with history context
        let system_prompt = if !history_context.is_empty() {
            format!("{}\n\n{}", base_system_prompt, history_context)
        } else {
            base_system_prompt.to_string()
        };

        let messages = vec![
            llm::ChatMessage {
                role: llm::Role::System,
                content: system_prompt,
            },
            llm::ChatMessage {
                role: llm::Role::User,
                content: format!("Voice command: \"{}\"", text),
            },
        ];
        
        let options = llm::ChatOptions {
            temperature: Some(0.1),
            json_object: true,
        };
        
        // Add user message to memory
        self.memory.add_user_message(text);
        
        let response = client.chat(&messages, options).await?;
        
        // Validate it's proper JSON
        let parsed: RouterResponse = serde_json::from_str(&response)?;
        
        // Add the routing decision to memory as assistant response
        let decision_summary = match &parsed.action {
            crate::types::RouterAction::LaunchClaude => {
                format!("Routing to Claude: {}", parsed.prompt.as_ref().unwrap_or(&"".to_string()))
            }
            crate::types::RouterAction::CannotParse => {
                format!("Cannot parse: {}", parsed.reason.as_ref().unwrap_or(&"unclear command".to_string()))
            }
        };
        self.memory.add_assistant_message(decision_summary);
        
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