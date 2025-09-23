use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::path::PathBuf;
use std::fs;

use anyhow::{Result, anyhow, Context};
use chrono::Utc;

use crate::artifacts::{ArtifactManager, ArtifactUpdateOutcome};
use crate::io_guard::{IoGuard, safe_read, safe_write_atomic};
use crate::router::{Intent, ProposedAction};

/// Represents a single action that can be executed by the orchestrator.
/// All file I/O must go through these actions.
#[derive(Debug, Clone)]
pub enum Action {
    /// Read a file and return its contents
    Read { 
        path: String,
    },
    /// Write content to a file (full replacement)
    Write { 
        path: String, 
        content: String,
    },
    /// Apply an edit patch to a file
    Edit { 
        path: String, 
        patch: String,
        patch_type: PatchType,
    },
    /// Process a turn with transcript and reply
    ProcessArtifacts { 
        transcript: String, 
        reply: String,
    },
}

/// Type of patch to apply
#[derive(Debug, Clone, Copy)]
pub enum PatchType {
    UnifiedDiff,
    YamlMerge,
}

/// The current state of the orchestrator's execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrchestratorState {
    /// Ready to receive new actions
    Conversing,
    /// Currently executing an action
    Executing,
    /// Action completed, transitioning back to conversing
    Completed,
}

impl std::fmt::Display for OrchestratorState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Conversing => write!(f, "conversing"),
            Self::Executing => write!(f, "executing"),
            Self::Completed => write!(f, "completed"),
        }
    }
}

/// Context for the current turn of conversation.
#[derive(Debug, Clone)]
pub struct TurnContext {
    /// Unique identifier for this turn
    pub turn_id: String,
    /// When the turn started
    pub started_at: chrono::DateTime<Utc>,
    /// The user's transcript for this turn
    pub transcript: Option<String>,
    /// The assistant's reply for this turn
    pub reply: Option<String>,
}

impl TurnContext {
    /// Create a new turn context with a unique ID.
    pub fn new() -> Self {
        let turn_id = format!(
            "{}-{:04}", 
            Utc::now().format("%Y%m%dT%H%M%S"),
            rand::random::<u16>() % 10000
        );
        
        Self {
            turn_id,
            started_at: Utc::now(),
            transcript: None,
            reply: None,
        }
    }
}

/// Result of processing an action.
pub struct ActionResult {
    pub artifact_outcome: Option<ArtifactUpdateOutcome>,
    pub read_content: Option<String>,
    pub write_success: bool,
    pub speak_text: Option<String>,  // Text that should be spoken
    pub completion_message: Option<String>, // Message to speak when action completes
}

/// Cache for last response (text and audio)
pub struct ResponseCache {
    pub last_text: Option<String>,
    pub last_audio: Option<Vec<u8>>,
}

/// The main orchestrator that ensures single-threaded execution of all actions.
/// This is the only component allowed to perform file I/O operations.
pub struct Orchestrator {
    /// Current execution state
    state: OrchestratorState,
    /// Queue of pending actions (FIFO)
    action_queue: VecDeque<Action>,
    /// Current turn context
    current_turn: Option<TurnContext>,
    /// Last proposal waiting for confirmation
    last_proposal: Option<ProposedAction>,
    /// Response cache for repeat last
    response_cache: ResponseCache,
    /// Flag for debug output
    debug_enabled: bool,
    /// Interrupt flag for stopping operations
    interrupt: Arc<AtomicBool>,
    /// Reference to artifact manager (temporary for Phase 0)
    artifact_manager: Option<ArtifactManager>,
    /// Content generator for creating descriptions and phasing
    generator: Option<ContentGenerator>,
    /// Conversation history for context
    conversation_history: Vec<String>,
}

impl Orchestrator {
    /// Create a new orchestrator instance.
    pub fn new() -> Self {
        let debug_enabled = std::env::var("WALKCOACH_DEBUG_QUEUE")
            .ok()
            .map(|v| v == "1" || v.to_lowercase() == "true")
            .unwrap_or(false);
        
        // Try to create generator, but don't fail if it can't be created
        let generator = ContentGenerator::new().ok();
        
        Self {
            state: OrchestratorState::Conversing,
            action_queue: VecDeque::new(),
            current_turn: None,
            last_proposal: None,
            response_cache: ResponseCache {
                last_text: None,
                last_audio: None,
            },
            debug_enabled,
            interrupt: Arc::new(AtomicBool::new(false)),
            artifact_manager: None,
            generator,
            conversation_history: Vec::new(),
        }
    }
    
    /// Set the artifact manager (temporary for Phase 0, will be refactored in Phase 1).
    pub fn set_artifact_manager(&mut self, manager: ArtifactManager) {
        self.artifact_manager = Some(manager);
    }
    
    /// Start a new turn of conversation.
    pub fn begin_turn(&mut self) -> TurnContext {
        let context = TurnContext::new();
        self.current_turn = Some(context.clone());
        self.debug_status("new turn started");
        context
    }
    
    /// Add a conversation turn to history for context
    pub fn add_to_history(&mut self, user_msg: &str, assistant_msg: &str) {
        self.conversation_history.push(format!("User: {}", user_msg));
        self.conversation_history.push(format!("Assistant: {}", assistant_msg));
        
        // Keep only last 10 turns for context (20 messages)
        if self.conversation_history.len() > 20 {
            self.conversation_history.drain(0..2);
        }
    }
    
    /// Enqueue an action for execution.
    /// Actions are processed in FIFO order.
    pub fn enqueue(&mut self, action: Action) -> Result<()> {
        if self.interrupt.load(Ordering::SeqCst) {
            return Err(anyhow!("Orchestrator interrupted"));
        }
        
        self.action_queue.push_back(action);
        self.debug_status("action enqueued");
        Ok(())
    }
    
    /// Execute the next action in the queue.
    /// Returns Some(ActionResult) if an action was executed, None if queue was empty.
    pub fn execute_next(&mut self) -> Result<Option<ActionResult>> {
        // Check for interrupt
        if self.interrupt.load(Ordering::SeqCst) {
            self.action_queue.clear();
            self.interrupt.store(false, Ordering::SeqCst);
            self.state = OrchestratorState::Conversing;
            self.debug_status("interrupted, queue cleared");
            return Ok(None);
        }
        
        // Can't execute if already executing
        if self.state == OrchestratorState::Executing {
            self.debug_status("already executing, skipping");
            return Ok(None);
        }
        
        // Get next action from queue
        let Some(action) = self.action_queue.pop_front() else {
            if self.state == OrchestratorState::Completed {
                self.state = OrchestratorState::Conversing;
                self.debug_status("completed -> conversing");
            }
            return Ok(None);
        };
        
        // Transition to executing
        self.state = OrchestratorState::Executing;
        self.debug_status("executing action");
        
        // Execute the action
        let result = self.apply_action(action)?;
        
        // Transition to completed
        self.state = OrchestratorState::Completed;
        self.debug_status("action completed");
        
        Ok(Some(result))
    }
    
    /// Apply a single action. This is where all I/O happens.
    /// All file operations are guarded to ensure only the orchestrator can perform them.
    fn apply_action(&mut self, action: Action) -> Result<ActionResult> {
        // Enable I/O for the duration of this action
        let _guard = IoGuard::new();
        
        match action {
            Action::Read { path } => {
                // Check if this is a cache read
                let content = if path == "cache:last" {
                    self.response_cache.last_text.clone()
                        .ok_or_else(|| anyhow!("No cached response"))?
                } else {
                    if self.debug_enabled {
                        eprintln!("[orchestrator] reading file: {}", path);
                    }
                    
                    let path_buf = PathBuf::from(&path);
                    let content = safe_read(&path_buf)
                        .with_context(|| format!("Failed to read {}", path))?;
                    
                    // Cache the content for repeat
                    self.response_cache.last_text = Some(content.clone());
                    content
                };
                
                Ok(ActionResult {
                    artifact_outcome: None,
                    read_content: Some(content.clone()),
                    write_success: false,
                    speak_text: Some(content),  // This will be spoken
                    completion_message: None,  // No completion for reads
                })
            }
            
            Action::Write { path, content } => {
                if self.debug_enabled {
                    eprintln!("[orchestrator] writing file: {}", path);
                }
                
                let path_buf = PathBuf::from(&path);
                
                // Create parent directory if needed
                if let Some(parent) = path_buf.parent() {
                    fs::create_dir_all(parent)
                        .with_context(|| format!("Failed to create parent directory for {}", path))?;
                }
                
                // Write atomically
                safe_write_atomic(&path_buf, content.as_bytes())
                    .with_context(|| format!("Failed to write {}", path))?;
                
                Ok(ActionResult {
                    artifact_outcome: None,
                    read_content: None,
                    write_success: true,
                    speak_text: None,
                    completion_message: Some("Done".to_string()),  // Narrate completion
                })
            }
            
            Action::Edit { path, patch, patch_type } => {
                if self.debug_enabled {
                    eprintln!("[orchestrator] editing file: {} ({:?})", path, patch_type);
                }
                
                // For Phase 1, we'll delegate to the existing artifact store logic
                // In future phases, this will be fully implemented here
                let path_buf = PathBuf::from(&path);
                
                // Read current content
                let current = if path_buf.exists() {
                    safe_read(&path_buf)?
                } else {
                    String::new()
                };
                
                // Apply patch based on type
                let updated = match patch_type {
                    PatchType::UnifiedDiff => {
                        // Use diffy to apply patch
                        let patch_obj = diffy::Patch::from_str(&patch)
                            .context("Failed to parse unified diff")?;
                        diffy::apply(&current, &patch_obj)
                            .context("Failed to apply diff")?
                    }
                    PatchType::YamlMerge => {
                        // For now, just return an error - will implement in later phase
                        return Err(anyhow!("YAML merge not yet implemented"));
                    }
                };
                
                // Write updated content
                safe_write_atomic(&path_buf, updated.as_bytes())?;
                
                Ok(ActionResult {
                    artifact_outcome: None,
                    read_content: None,
                    write_success: true,
                    speak_text: None,
                    completion_message: Some("Done".to_string()),  // Narrate completion
                })
            }
            
            Action::ProcessArtifacts { transcript, reply } => {
                // Update turn context
                if let Some(turn) = &mut self.current_turn {
                    turn.transcript = Some(transcript.clone());
                    turn.reply = Some(reply.clone());
                }
                
                // Process artifacts through manager
                let artifact_outcome = if let Some(manager) = &self.artifact_manager {
                    
                    match manager.process_turn(&transcript, &reply) {
                        Ok(outcome) => outcome,
                        Err(err) => {
                            eprintln!("Artifact processing failed: {err:?}");
                            None
                        }
                    }
                } else {
                    None
                };
                
                Ok(ActionResult {
                    artifact_outcome,
                    read_content: None,
                    write_success: false,
                    speak_text: None,
                    completion_message: None,
                })
            }
        }
    }
    
    /// Check if there are pending actions in the queue.
    pub fn has_pending(&self) -> bool {
        !self.action_queue.is_empty()
    }
    
    /// Get the current queue size.
    pub fn queue_size(&self) -> usize {
        self.action_queue.len()
    }
    
    /// Get the current state.
    pub fn state(&self) -> OrchestratorState {
        self.state
    }
    
    /// Request an interrupt of the current operation.
    pub fn interrupt(&self) {
        self.interrupt.store(true, Ordering::SeqCst);
    }
    
    /// Clear the interrupt flag.
    pub fn clear_interrupt(&self) {
        self.interrupt.store(false, Ordering::SeqCst);
    }
    
    /// Get a handle to check for interrupts (for long-running operations).
    pub fn interrupt_handle(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.interrupt)
    }
    
    /// Process an intent from the router.
    pub fn handle_intent(&mut self, intent: Intent) -> Result<String> {
        match intent {
            Intent::Directive { action } => {
                self.execute_proposed_action(action)?;
                Ok("executing".to_string())
            }
            Intent::Proposal { action, question } => {
                self.last_proposal = Some(action);
                Ok(question)
            }
            Intent::Confirmation { confirmed } => {
                if confirmed {
                    if let Some(action) = self.last_proposal.take() {
                        self.execute_proposed_action(action)?;
                        Ok("executing".to_string())
                    } else {
                        Ok("no proposal to confirm".to_string())
                    }
                } else {
                    self.last_proposal = None;
                    Ok("cancelled".to_string())
                }
            }
            Intent::Info { message } => {
                Ok(message)
            }
        }
    }
    
    /// Execute a proposed action by converting it to an Action and enqueueing it.
    fn execute_proposed_action(&mut self, proposed: ProposedAction) -> Result<()> {
        // Enable I/O for reading during action preparation
        let _guard = IoGuard::new();
        
        let action = match proposed {
            ProposedAction::WriteDescription => {
                // Use generator if available, otherwise fallback
                let content = if let Some(ref generator) = self.generator {
                    let context = self.conversation_history.join("\n");
                    generator.generate_description(&context)
                        .unwrap_or_else(|err| {
                            eprintln!("Generator failed: {err:?}, using fallback");
                            "# Project Description\n\nThis is a voice-first project specification tool.\n\nThe system allows you to:\n- Create and manage project descriptions\n- Define project phases\n- Use voice commands for all interactions\n- Get audio feedback through text-to-speech\n\nAll operations are single-threaded and sequential for predictability.\n".to_string()
                        })
                } else {
                    "# Project Description\n\nThis is a voice-first project specification tool.\n\nThe system allows you to:\n- Create and manage project descriptions\n- Define project phases\n- Use voice commands for all interactions\n- Get audio feedback through text-to-speech\n\nAll operations are single-threaded and sequential for predictability.\n".to_string()
                };
                
                Action::Write {
                    path: "artifacts/description.md".to_string(),
                    content,
                }
            }
            ProposedAction::WritePhasing => {
                // Use generator if available  
                let content = if let Some(ref generator) = self.generator {
                    // Try to read existing description for context
                    let description = safe_read(&PathBuf::from("artifacts/description.md"))
                        .unwrap_or_else(|_| String::new());
                    let context = self.conversation_history.join("\n");
                    
                    generator.generate_phasing(&description, &context)
                        .unwrap_or_else(|err| {
                            eprintln!("Generator failed: {err:?}, using fallback");
                            "# Project Phases\n\n## Phase 1: Foundation\nSet up core infrastructure and basic voice input.\n\n## Phase 2: Router Implementation  \nAdd intelligent routing of commands through LLM.\n\n## Phase 3: Audio Integration\nImplement text-to-speech for all read operations.\n\n## Phase 4: Content Generation\nAdd real content generation using LLMs.\n\n## Phase 5: Refinement\nPolish user experience and error handling.\n".to_string()
                        })
                } else {
                    "# Project Phases\n\n## Phase 1: Foundation\nSet up core infrastructure and basic voice input.\n\n## Phase 2: Router Implementation  \nAdd intelligent routing of commands through LLM.\n\n## Phase 3: Audio Integration\nImplement text-to-speech for all read operations.\n\n## Phase 4: Content Generation\nAdd real content generation using LLMs.\n\n## Phase 5: Refinement\nPolish user experience and error handling.\n".to_string()
                };
                
                Action::Write {
                    path: "artifacts/phasing.md".to_string(),
                    content,
                }
            }
            ProposedAction::ReadDescription => {
                Action::Read {
                    path: "artifacts/description.md".to_string(),
                }
            }
            ProposedAction::ReadPhasing => {
                Action::Read {
                    path: "artifacts/phasing.md".to_string(),
                }
            }
            ProposedAction::EditDescription { change } => {
                // Read current content, apply edit via generator, then write
                let current_path = PathBuf::from("artifacts/description.md");
                let current_content = if current_path.exists() {
                    safe_read(&current_path)?
                } else {
                    String::new()
                };
                
                let updated_content = if let Some(ref generator) = self.generator {
                    generator.generate_edit(&current_content, &change)
                        .unwrap_or(current_content.clone())
                } else {
                    // Simple fallback: append the change
                    format!("{}\n\n{}", current_content, change)
                };
                
                Action::Write {
                    path: "artifacts/description.md".to_string(),
                    content: updated_content,
                }
            }
            ProposedAction::EditPhasing { phase: _, change } => {
                // Read current content, apply edit via generator, then write
                let current_path = PathBuf::from("artifacts/phasing.md");
                let current_content = if current_path.exists() {
                    safe_read(&current_path)?
                } else {
                    String::new()
                };
                
                let updated_content = if let Some(ref generator) = self.generator {
                    generator.generate_edit(&current_content, &change)
                        .unwrap_or(current_content.clone())
                } else {
                    // Simple fallback: append the change
                    format!("{}\n\n{}", current_content, change)
                };
                
                Action::Write {
                    path: "artifacts/phasing.md".to_string(),
                    content: updated_content,
                }
            }
            ProposedAction::RepeatLast => {
                // Return cached text to be spoken
                if self.response_cache.last_text.is_some() {
                    return self.enqueue(Action::Read { 
                        path: "cache:last".to_string()  // Special marker for cached content
                    });
                }
                return Ok(());
            }
            ProposedAction::Stop => {
                self.interrupt();
                return Ok(());
            }
        };
        
        self.enqueue(action)
    }
    
    /// Print debug status if debug mode is enabled.
    fn debug_status(&self, context: &str) {
        if self.debug_enabled {
            // Only log important state changes
            if context.contains("executing") || context.contains("interrupted") {
                eprintln!(
                    "[orchestrator] {}: queue={}",
                    context,
                    self.action_queue.len()
                );
            }
        }
    }
}

// Content generator for creating descriptions and phasing
use std::time::Duration;
use reqwest::blocking::Client as HttpClient;
use serde_json::json;

/// Generator for creating artifact content using LLMs
struct ContentGenerator {
    http: HttpClient,
    api_key: String,
    base_url: String,
    model: String,
}

impl ContentGenerator {
    fn new() -> Result<Self> {
        let api_key = std::env::var("GROQ_API_KEY")
            .context("GROQ_API_KEY required for content generation")?;
            
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("Failed to build HTTP client for generator")?;
            
        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());
            
        // Use same model as router for now (k2)
        let model = std::env::var("GROQ_GENERATOR_MODEL")
            .unwrap_or_else(|_| std::env::var("GROQ_LLM_MODEL")
                .unwrap_or_else(|_| "moonshotai/kimi-k2-instruct-0905".to_string()));
            
        Ok(Self {
            http,
            api_key,
            base_url,
            model,
        })
    }
    
    /// Generate a project description based on conversation context
    fn generate_description(&self, context: &str) -> Result<String> {
        let prompt = format!(
            "Based on this conversation context, write a clear, concise project description in markdown format:\n\n{}\n\nWrite a professional project description with:\n- A brief overview paragraph\n- Key features/capabilities (as bullet points)\n- Main technical approach\n\nKeep it focused and under 300 words.",
            context
        );
        
        self.generate_content(&prompt)
    }
    
    /// Generate a phasing plan based on project description
    fn generate_phasing(&self, description: &str, context: &str) -> Result<String> {
        let prompt = format!(
            "Based on this project description:\n{}\n\nAnd this additional context:\n{}\n\nCreate a phasing plan in markdown format with 4-6 phases. Each phase should have:\n- A clear phase title\n- 2-3 bullet points describing the deliverables\n- Keep each phase focused and achievable\n\nFormat as:\n## Phase 1: [Title]\n- Deliverable 1\n- Deliverable 2\n\netc.",
            description, context
        );
        
        self.generate_content(&prompt)
    }
    
    /// Generate an edit/update based on user request
    fn generate_edit(&self, current_content: &str, edit_request: &str) -> Result<String> {
        let prompt = format!(
            "Current document:\n{}\n\nUser request: {}\n\nGenerate the updated document with the requested change applied. Return the complete updated document, not just the changes.",
            current_content, edit_request
        );
        
        self.generate_content(&prompt)
    }
    
    /// Core content generation using LLM
    fn generate_content(&self, prompt: &str) -> Result<String> {
        let body = json!({
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a technical documentation writer. Generate clear, professional content based on the user's requirements. Use markdown formatting."
                },
                {
                    "role": "user", 
                    "content": prompt
                }
            ],
            "temperature": 0.7,
            "max_tokens": 1000,
        });
        
        let url = format!("{}/openai/v1/chat/completions", self.base_url.trim_end_matches('/'));
        
        let response = self.http
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("Generator LLM request failed")?;
            
        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().unwrap_or_else(|_| "Unknown error".to_string());
            eprintln!("Generator LLM error: Status={}, Body={}", status, error_text);
            return Err(anyhow!("Generator LLM returned error: {}", status));
        }
            
        let json: serde_json::Value = response.json()
            .context("Failed to parse generator response")?;
            
        let content = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .trim();
            
        if content.is_empty() {
            return Err(anyhow!("Generator returned empty content"));
        }
        
        Ok(content.to_string())
    }
}