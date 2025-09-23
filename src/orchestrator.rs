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
}

impl Orchestrator {
    /// Create a new orchestrator instance.
    pub fn new() -> Self {
        let debug_enabled = std::env::var("WALKCOACH_DEBUG_QUEUE")
            .ok()
            .map(|v| v == "1" || v.to_lowercase() == "true")
            .unwrap_or(false);
        
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
        let action = match proposed {
            ProposedAction::WriteDescription => {
                // Basic content for Phase 3 testing
                // In Phase 5, this will use generators  
                Action::Write {
                    path: "artifacts/description.md".to_string(),
                    content: "# Project Description\n\nThis is a voice-first project specification tool.\n\nThe system allows you to:\n- Create and manage project descriptions\n- Define project phases\n- Use voice commands for all interactions\n- Get audio feedback through text-to-speech\n\nAll operations are single-threaded and sequential for predictability.\n".to_string(),
                }
            }
            ProposedAction::WritePhasing => {
                Action::Write {
                    path: "artifacts/phasing.md".to_string(),
                    content: "# Project Phases\n\n## Phase 1: Foundation\nSet up core infrastructure and basic voice input.\n\n## Phase 2: Router Implementation  \nAdd intelligent routing of commands through LLM.\n\n## Phase 3: Audio Integration\nImplement text-to-speech for all read operations.\n\n## Phase 4: Content Generation\nAdd real content generation using LLMs.\n\n## Phase 5: Refinement\nPolish user experience and error handling.\n".to_string(),
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
            ProposedAction::EditDescription { change: _ } => {
                // For now, return a placeholder
                // In Phase 6, this will generate proper diffs
                return Ok(());
            }
            ProposedAction::EditPhasing { phase: _, change: _ } => {
                // For now, return a placeholder
                return Ok(());
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

// We need to add rand for turn IDs
// This will be added to Cargo.toml dependencies