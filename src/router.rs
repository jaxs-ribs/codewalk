use std::time::Duration;
use anyhow::{Result, anyhow, Context};
use reqwest::blocking::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_json::json;

/// Represents the intent derived from user input.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Intent {
    /// A proposal that requires confirmation (e.g., "write the description?")
    Proposal {
        action: ProposedAction,
        question: String,
    },
    /// A direct command to execute immediately
    Directive {
        action: ProposedAction,
    },
    /// User confirmation (yes/no)
    Confirmation {
        confirmed: bool,
    },
    /// Informational response, no action needed
    Info {
        message: String,
    },
}

/// Actions that can be proposed or directed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ProposedAction {
    WriteDescription,
    WritePhasing,
    ReadDescription,
    ReadPhasing,
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
            
        let api_key = std::env::var("GROQ_API_KEY")
            .context("GROQ_API_KEY required for router")?;
            
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
            debug 
        })
    }
    
    /// Parse user input using LLM for intelligent routing.
    pub fn parse_user_input(&self, input: &str) -> Result<Intent> {
        // Everything goes through LLM router for natural language understanding
        self.route_with_llm(input)
    }
    
    /// Use LLM to determine intent from user input
    fn route_with_llm(&self, input: &str) -> Result<Intent> {
        let system_prompt = r#"You are a router that determines user intent for a voice-controlled artifact editor.

Respond with JSON only:
{
  "intent_type": "directive|proposal|confirmation|info",
  "action": "write_description|write_phasing|read_description|read_phasing|edit_description|edit_phasing|stop|repeat_last|none",
  "confirmed": true/false (only for confirmation),
  "question": "question to ask if proposal"
}

Rules:
- "directive" = execute immediately (clear command)
- "proposal" = ask for confirmation first
- "confirmation" = user confirming/denying (yes/no/sure/nah/etc)
- "info" = just informational
- Use "edit_*" actions when user wants to change/modify/replace/update existing content with specific text
- Use "write_*" actions only when generating new content from scratch

Examples:
"write the description" -> {"intent_type": "directive", "action": "write_description"}
"replace the phasing with I love you" -> {"intent_type": "directive", "action": "edit_phasing"}
"change the description to say X" -> {"intent_type": "directive", "action": "edit_description"}
"description please" -> {"intent_type": "directive", "action": "read_description"}  
"can you write it?" -> {"intent_type": "proposal", "action": "write_description", "question": "Write the description?"}
"yes" -> {"intent_type": "confirmation", "confirmed": true}
"i want to build X" -> {"intent_type": "info", "action": "none"}"#;

        let body = json!({
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": input}
            ],
            "temperature": 0.0,
            "max_tokens": 100,
            "response_format": {"type": "json_object"}
        });
        
        let url = format!("{}/openai/v1/chat/completions", self.base_url.trim_end_matches('/'));
        
        let response = self.http
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("Router LLM request failed")?;
            
        let response = response
            .error_for_status()
            .context("Router LLM returned error")?;
            
        let json: serde_json::Value = response.json()
            .context("Failed to parse router response")?;
            
        let content = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("{}");
            
        if self.debug {
            eprintln!("[router] LLM response: {}", content);
        } else if std::env::var("WALKCOACH_DEBUG_ROUTER_LITE").is_ok() {
            // Lighter debug output - just show intent and action
            if let Ok(parsed) = serde_json::from_str::<RouterResponse>(content) {
                eprintln!("[router] {} -> {}", 
                    parsed.intent_type,
                    parsed.action.as_deref().unwrap_or("none")
                );
            }
        }
            
        let router_response: RouterResponse = serde_json::from_str(content)
            .context("Failed to parse router JSON")?;
            
        // Convert to Intent
        match router_response.intent_type.as_str() {
            "directive" => {
                let action_str = router_response.action.unwrap_or_else(|| "none".to_string());
                match self.parse_action_with_context(&action_str, input) {
                    Ok(action) => Ok(Intent::Directive { action }),
                    Err(_) => Ok(Intent::Info { message: "Got it".to_string() })
                }
            }
            "proposal" => {
                let action_str = router_response.action.unwrap_or_else(|| "none".to_string());
                match self.parse_action_with_context(&action_str, input) {
                    Ok(action) => {
                        let question = router_response.question.unwrap_or_else(|| {
                            format!("Should I {}?", action_str.replace('_', " "))
                        });
                        Ok(Intent::Proposal { action, question })
                    }
                    Err(_) => Ok(Intent::Info { message: "What would you like?".to_string() })
                }
            }
            "confirmation" => {
                Ok(Intent::Confirmation { 
                    confirmed: router_response.confirmed.unwrap_or(false)
                })
            }
            _ => Ok(Intent::Info { 
                message: "Got it".to_string()
            })
        }
    }
    
    fn parse_action(&self, action: &str) -> Result<ProposedAction> {
        self.parse_action_with_context(action, "")
    }
    
    fn parse_action_with_context(&self, action: &str, input: &str) -> Result<ProposedAction> {
        match action {
            "write_description" => Ok(ProposedAction::WriteDescription),
            "write_phasing" => Ok(ProposedAction::WritePhasing),
            "read_description" => Ok(ProposedAction::ReadDescription),
            "read_phasing" => Ok(ProposedAction::ReadPhasing),
            "edit_description" => Ok(ProposedAction::EditDescription { 
                change: input.to_string()  // Use the full input as the change
            }),
            "edit_phasing" => Ok(ProposedAction::EditPhasing { 
                phase: None, 
                change: input.to_string()  // Use the full input as the change
            }),
            "stop" => Ok(ProposedAction::Stop),
            "repeat_last" => Ok(ProposedAction::RepeatLast),
            _ => Err(anyhow!("Unknown action: {}", action))
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
        let is_proposal = response.ends_with('?') || 
                         response_lower.contains("should i") ||
                         response_lower.contains("would you like");
        
        // Try to extract the action from the response
        let action = self.extract_action_from_text(&transcript, &response_lower);
        
        match action {
            Some(action) if is_proposal => {
                Intent::Proposal {
                    action,
                    question: response.to_string(),
                }
            }
            Some(action) => {
                Intent::Directive { action }
            }
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
        assert_eq!(intent, Some(Intent::Directive {
            action: ProposedAction::WriteDescription,
        }));
        
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
        let intent = router.parse_assistant_response(
            "description please",
            "Should I write the description?"
        );
        if let Intent::Proposal { action, .. } = intent {
            assert_eq!(action, ProposedAction::WriteDescription);
        } else {
            panic!("Expected proposal");
        }
        
        // Test directive detection
        let intent = router.parse_assistant_response(
            "write the description",
            "Writing the description now"
        );
        if let Intent::Directive { action } = intent {
            assert_eq!(action, ProposedAction::WriteDescription);
        } else {
            panic!("Expected directive");
        }
    }
}