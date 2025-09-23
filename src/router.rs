use anyhow::{Context, Result, anyhow};
use reqwest::blocking::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Duration;

/// Represents the intent derived from user input.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Intent {
    /// A proposal that requires confirmation (e.g., "write the description?")
    Proposal {
        action: ProposedAction,
        question: String,
    },
    /// A direct command to execute immediately
    Directive { action: ProposedAction },
    /// User confirmation (yes/no)
    Confirmation { confirmed: bool },
    /// Informational response, no action needed
    Info { message: String },
}

/// Actions that can be proposed or directed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ProposedAction {
    WriteDescription,
    WritePhasing,
    ReadDescription,
    ReadPhasing,
    ReadDescriptionSlowly,
    ReadPhasingSlowly,
    ReadPhase { number: u32 },
    EditDescription { change: String },
    EditPhasing { phase: Option<u32>, change: String },
    RepeatLast,
    Stop,
}

/// LLM response for routing
#[derive(Debug, Deserialize)]
struct RouterResponse {
    intent_type: String,
    action: Option<String>,
    confirmed: Option<bool>,
    question: Option<String>,
    phase_number: Option<u32>,
}

/// Router that interprets user input and assistant responses into intents.
pub struct Router {
    http: HttpClient,
    api_key: String,
    base_url: String,
    model: String,
    debug: bool,
}

impl Router {
    /// Create a new router instance.
    pub fn new() -> Result<Self> {
        let debug = std::env::var("WALKCOACH_DEBUG_ROUTER")
            .ok()
            .map(|v| v == "1" || v.to_lowercase() == "true")
            .unwrap_or(false);

        let api_key = std::env::var("GROQ_API_KEY").context("GROQ_API_KEY required for router")?;

        let http = HttpClient::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("Failed to build HTTP client for router")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());

        let model = std::env::var("GROQ_LLM_MODEL")
            .unwrap_or_else(|_| "moonshotai/kimi-k2-instruct-0905".to_string());

        Ok(Self {
            http,
            api_key,
            base_url,
            model,
            debug,
        })
    }

    /// Parse user input using LLM for intelligent routing.
    pub fn parse_user_input(&self, input: &str) -> Result<Intent> {
        // Everything goes through LLM router for natural language understanding
        self.route_with_llm(input, None)
    }
    
    /// Parse user input with conversation context
    pub fn parse_user_input_with_context(&self, input: &str, context: &[String]) -> Result<Intent> {
        self.route_with_llm(input, Some(context))
    }

    /// Use LLM to determine intent from user input
    fn route_with_llm(&self, input: &str, context: Option<&[String]>) -> Result<Intent> {
        let system_prompt = r#"You are a router that determines user intent for a voice-controlled artifact editor.

Respond with JSON only:
{
  "intent_type": "directive|proposal|confirmation|info",
  "action": "write_description|write_phasing|read_description|read_phasing|read_description_slowly|read_phasing_slowly|read_phase_N|edit_description|edit_phasing|stop|repeat_last|none",
  "confirmed": true/false (only for confirmation),
  "question": "question to ask if proposal",
  "phase_number": N (only for read_phase_N action)
}

CRITICAL RULES - CONVERSATION FIRST:
- Most user input is conversational (intent_type: "info", action: "none")
- Only use write/edit actions for EXPLICIT COMMANDS like "write the description", "create the phasing", "edit the description"
- When user discusses ideas, plans, or concepts WITHOUT explicit write commands, treat as "info"
- "proposal" should be used when YOU want to suggest writing after gathering enough context
- "directive" requires an explicit command verb (write, create, edit, read, etc.)

Intent Types:
- "directive" = ONLY for explicit commands with clear action verbs
- "proposal" = when YOU want to suggest an action (include a question)
- "confirmation" = user confirming/denying (yes/no/sure/nah/etc)
- "info" = conversational, discussing ideas, planning, brainstorming (DEFAULT)

Action Rules:
- Use "write_*" ONLY when user explicitly says "write", "create", or similar command verb
- Use "edit_*" ONLY when user explicitly says "edit", "change", "modify", "update" with specific text
- Use "none" for all conversational, planning, or idea discussion
- Use "read_*_slowly" when user asks to read slowly, in chunks, or step by step
- Use "read_phase_N" when user asks for a specific phase number (set phase_number field)

Examples:
"I'm thinking of building an app" -> {"intent_type": "info", "action": "none"}
"It should help people walk" -> {"intent_type": "info", "action": "none"}
"The app is called Code Walk" -> {"intent_type": "info", "action": "none"}
"write the description" -> {"intent_type": "directive", "action": "write_description"}
"create a description for me" -> {"intent_type": "directive", "action": "write_description"}
"let's write the phasing" -> {"intent_type": "directive", "action": "write_phasing"}
"can you write the description?" -> {"intent_type": "directive", "action": "write_description"}
"should we write the description?" -> {"intent_type": "info", "action": "none"}
"read the phasing" -> {"intent_type": "directive", "action": "read_phasing"}
"what's in the description?" -> {"intent_type": "directive", "action": "read_description"}
"change phase 2 to focus on testing" -> {"intent_type": "directive", "action": "edit_phasing", "phase_number": 2}
"I want the first phase to be about setup" -> {"intent_type": "info", "action": "none"}
"yes" -> {"intent_type": "confirmation", "confirmed": true}
"sure" -> {"intent_type": "confirmation", "confirmed": true}
"no" -> {"intent_type": "confirmation", "confirmed": false}"#;

        // Build messages with optional context
        let mut messages = vec![
            json!({"role": "system", "content": system_prompt}),
        ];
        
        // Add conversation context if provided
        if let Some(ctx) = context {
            if !ctx.is_empty() {
                let context_str = ctx.join("\n");
                messages.push(json!({
                    "role": "system", 
                    "content": format!("Recent conversation for context:\n{}", context_str)
                }));
            }
        }
        
        messages.push(json!({"role": "user", "content": input}));
        
        let body = json!({
            "model": self.model,
            "messages": messages,
            "temperature": 0.0,
            "max_tokens": 100,
            "response_format": {"type": "json_object"}
        });

        let url = format!(
            "{}/openai/v1/chat/completions",
            self.base_url.trim_end_matches('/')
        );

        // Try the request with retry on network errors
        let mut retries = 2;
        let json = loop {
            let result = self
                .http
                .post(&url)
                .bearer_auth(&self.api_key)
                .json(&body)
                .send();
            
            match result {
                Ok(response) => {
                    match response.error_for_status() {
                        Ok(resp) => {
                            match resp.json::<serde_json::Value>() {
                                Ok(json) => break json,
                                Err(e) => {
                                    if retries > 0 {
                                        retries -= 1;
                                        eprintln!("[router] Parse error, retrying: {}", e);
                                        std::thread::sleep(std::time::Duration::from_millis(500));
                                        continue;
                                    }
                                    // Fallback to conversational on parse errors
                                    return Ok(Intent::Info { message: "I understand".to_string() });
                                }
                            }
                        }
                        Err(e) => {
                            if retries > 0 && (e.status() == Some(reqwest::StatusCode::SERVICE_UNAVAILABLE) 
                                || e.status() == Some(reqwest::StatusCode::GATEWAY_TIMEOUT)
                                || e.status() == Some(reqwest::StatusCode::TOO_MANY_REQUESTS)) {
                                retries -= 1;
                                eprintln!("[router] HTTP error {}, retrying...", e.status().unwrap());
                                std::thread::sleep(std::time::Duration::from_millis(1000));
                                continue;
                            }
                            // Fallback to conversational on non-retryable errors
                            eprintln!("[router] LLM error, falling back to conversational: {}", e);
                            return Ok(Intent::Info { message: "I understand".to_string() });
                        }
                    }
                }
                Err(e) => {
                    if retries > 0 {
                        retries -= 1;
                        eprintln!("[router] Network error, retrying: {}", e);
                        std::thread::sleep(std::time::Duration::from_millis(1000));
                        continue;
                    }
                    // Fallback to conversational on network errors
                    eprintln!("[router] Network failure, falling back to conversational: {}", e);
                    return Ok(Intent::Info { message: "I understand".to_string() });
                }
            }
        };

        let content = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("{}");

        if self.debug {
            eprintln!("[router] LLM response: {}", content);
        } else if std::env::var("WALKCOACH_DEBUG_ROUTER_LITE").is_ok() {
            // Lighter debug output - just show intent and action
            if let Ok(parsed) = serde_json::from_str::<RouterResponse>(content) {
                eprintln!(
                    "[router] {} -> {}",
                    parsed.intent_type,
                    parsed.action.as_deref().unwrap_or("none")
                );
            }
        }

        let router_response: RouterResponse =
            serde_json::from_str(content).context("Failed to parse router JSON")?;

        // Convert to Intent
        match router_response.intent_type.as_str() {
            "directive" => {
                let action_str = router_response.action.unwrap_or_else(|| "none".to_string());
                match self.parse_action_with_context(&action_str, input, router_response.phase_number) {
                    Ok(action) => Ok(Intent::Directive { action }),
                    Err(_) => Ok(Intent::Info {
                        message: "Got it".to_string(),
                    }),
                }
            }
            "proposal" => {
                let action_str = router_response.action.unwrap_or_else(|| "none".to_string());
                match self.parse_action_with_context(&action_str, input, router_response.phase_number) {
                    Ok(action) => {
                        let question = router_response.question.unwrap_or_else(|| {
                            format!("Should I {}?", action_str.replace('_', " "))
                        });
                        Ok(Intent::Proposal { action, question })
                    }
                    Err(_) => Ok(Intent::Info {
                        message: "What would you like?".to_string(),
                    }),
                }
            }
            "confirmation" => Ok(Intent::Confirmation {
                confirmed: router_response.confirmed.unwrap_or(false),
            }),
            _ => Ok(Intent::Info {
                message: "Got it".to_string(),
            }),
        }
    }

    fn parse_action(&self, action: &str) -> Result<ProposedAction> {
        self.parse_action_with_context(action, "", None)
    }

    fn parse_action_with_context(&self, action: &str, input: &str, phase_number: Option<u32>) -> Result<ProposedAction> {
        match action {
            "write_description" => Ok(ProposedAction::WriteDescription),
            "write_phasing" => Ok(ProposedAction::WritePhasing),
            "read_description" => Ok(ProposedAction::ReadDescription),
            "read_phasing" => Ok(ProposedAction::ReadPhasing),
            "read_description_slowly" => Ok(ProposedAction::ReadDescriptionSlowly),
            "read_phasing_slowly" => Ok(ProposedAction::ReadPhasingSlowly),
            "read_phase_N" => {
                if let Some(number) = phase_number {
                    Ok(ProposedAction::ReadPhase { number })
                } else {
                    Err(anyhow!("Phase number required for read_phase_N"))
                }
            }
            "edit_description" => Ok(ProposedAction::EditDescription {
                change: input.to_string(), // Use the full input as the change
            }),
            "edit_phasing" => Ok(ProposedAction::EditPhasing {
                phase: phase_number,
                change: input.to_string(), // Use the full input as the change
            }),
            "stop" => Ok(ProposedAction::Stop),
            "repeat_last" => Ok(ProposedAction::RepeatLast),
            _ => Err(anyhow!("Unknown action: {}", action)),
        }
    }

    /// Parse assistant's response to extract intent.
    /// The assistant should respond with structured markers we can parse.
    pub fn parse_assistant_response(&self, transcript: &str, response: &str) -> Intent {
        if self.debug {
            eprintln!("[router] parsing assistant response: {}", response);
        }

        // Look for structured markers in response
        // For Phase 2, we'll do simple pattern matching
        // In later phases, this could use JSON or more structured format

        let response_lower = response.to_lowercase();

        // Check if it's a proposal (ends with question mark or contains "should i")
        let is_proposal = response.ends_with('?')
            || response_lower.contains("should i")
            || response_lower.contains("would you like");

        // Try to extract the action from the response
        let action = self.extract_action_from_text(&transcript, &response_lower);

        match action {
            Some(action) if is_proposal => Intent::Proposal {
                action,
                question: response.to_string(),
            },
            Some(action) => Intent::Directive { action },
            None => {
                // Default to info if we can't determine an action
                Intent::Info {
                    message: response.to_string(),
                }
            }
        }
    }

    /// Extract action from text using pattern matching.
    fn extract_action_from_text(&self, transcript: &str, text: &str) -> Option<ProposedAction> {
        // Check user's original request too
        let combined = format!("{} {}", transcript.to_lowercase(), text);

        if combined.contains("write") && combined.contains("description") {
            return Some(ProposedAction::WriteDescription);
        }
        if combined.contains("write") && combined.contains("phasing") {
            return Some(ProposedAction::WritePhasing);
        }
        if combined.contains("read") && combined.contains("description") {
            return Some(ProposedAction::ReadDescription);
        }
        if combined.contains("read") && combined.contains("phasing") {
            return Some(ProposedAction::ReadPhasing);
        }
        if combined.contains("edit") && combined.contains("description") {
            // Try to extract the change
            let change = self.extract_edit_content(transcript);
            return Some(ProposedAction::EditDescription { change });
        }
        if combined.contains("edit") && combined.contains("phas") {
            // Try to extract phase number and change
            let phase = self.extract_phase_number(&combined);
            let change = self.extract_edit_content(transcript);
            return Some(ProposedAction::EditPhasing { phase, change });
        }

        None
    }

    /// Extract edit content from user input.
    fn extract_edit_content(&self, text: &str) -> String {
        // For now, return the whole text
        // In future phases, we'll parse this better
        text.to_string()
    }

    /// Extract phase number from text.
    fn extract_phase_number(&self, text: &str) -> Option<u32> {
        // Look for "phase one", "phase 1", etc.
        if text.contains("phase one") || text.contains("phase 1") {
            return Some(1);
        }
        if text.contains("phase two") || text.contains("phase 2") {
            return Some(2);
        }
        if text.contains("phase three") || text.contains("phase 3") {
            return Some(3);
        }
        // Add more as needed

        // Try to find a number after "phase"
        if let Some(idx) = text.find("phase ") {
            let after_phase = &text[idx + 6..];
            if let Some(end_idx) = after_phase.find(|c: char| !c.is_ascii_digit()) {
                if let Ok(num) = after_phase[..end_idx].parse::<u32>() {
                    return Some(num);
                }
            }
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_direct_commands() {
        let router = Router::new();

        // Test direct write command
        let intent = router.parse_user_input("write the description");
        assert_eq!(
            intent,
            Some(Intent::Directive {
                action: ProposedAction::WriteDescription,
            })
        );

        // Test confirmation
        let intent = router.parse_user_input("yes");
        assert_eq!(intent, Some(Intent::Confirmation { confirmed: true }));

        // Test something that needs LLM
        let intent = router.parse_user_input("can you help me with the description?");
        assert_eq!(intent, None);
    }

    #[test]
    fn test_assistant_response_parsing() {
        let router = Router::new();

        // Test proposal detection
        let intent = router
            .parse_assistant_response("description please", "Should I write the description?");
        if let Intent::Proposal { action, .. } = intent {
            assert_eq!(action, ProposedAction::WriteDescription);
        } else {
            panic!("Expected proposal");
        }

        // Test directive detection
        let intent =
            router.parse_assistant_response("write the description", "Writing the description now");
        if let Intent::Directive { action } = intent {
            assert_eq!(action, ProposedAction::WriteDescription);
        } else {
            panic!("Expected directive");
        }
    }
}
