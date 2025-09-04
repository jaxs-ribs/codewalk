use anyhow::Result;
use router::RouterAction;
use crate::app::App;
use crate::types::{Mode, SessionAction};
use crate::constants::prefixes;

impl App {
    /// Handle confirmation response from user when in ConfirmingExecutor mode
    pub async fn handle_confirmation_response(&mut self, text: &str) -> Result<()> {
        if self.mode != Mode::ConfirmingExecutor {
            return Ok(());
        }
        
        // Get the pending executor info
        let pending = match &self.pending_executor {
            Some(p) => p.clone(),
            None => {
                self.mode = Mode::Idle;
                return Ok(());
            }
        };
        
        // Use the confirmation analyzer directly, not the LLM
        // The LLM would misinterpret "yes" as a status query
        let action = router::confirmation::analyze_confirmation_response(text);
        let response = router::confirmation::create_confirmation_response(action);
        
        match response.action {
            RouterAction::ContinuePrevious => {
                if let Some(session_id) = &self.last_completed_session_id {
                    let short_id = &session_id[..8.min(session_id.len())];
                    self.append_output(format!("{} ✓ Continuing previous session ({})", prefixes::EXEC, short_id));
                } else {
                    self.append_output(format!("{} ✓ Will continue previous session", prefixes::EXEC));
                }
                // Update pending executor with action
                if let Some(ref mut pending) = self.pending_executor {
                    pending.session_action = Some(SessionAction::ContinuePrevious);
                }
                self.launch_executor_with_action(SessionAction::ContinuePrevious).await?;
            }
            
            RouterAction::StartNew => {
                self.append_output(format!("{} ✓ Starting fresh Claude session", prefixes::EXEC));
                if let Some(ref mut pending) = self.pending_executor {
                    pending.session_action = Some(SessionAction::StartNew);
                }
                self.launch_executor_with_action(SessionAction::StartNew).await?;
            }
            
            RouterAction::DeclineSession => {
                self.append_output(format!("{} ✗ Cancelled - Claude session not started", prefixes::EXEC));
                self.pending_executor = None;
                self.mode = Mode::Idle;
            }
            
            RouterAction::AmbiguousConfirmation => {
                if pending.is_initial_prompt {
                    // First ambiguous response - ask for clarification
                    let clarification_msg = if let Some(summary) = &self.last_session_summary {
                        format!("{} 🤔 Would you like to:\n   • Continue previous ({})?\n   • Start new session?\n   • Cancel?\n   Say 'continue', 'new', or 'no'", 
                            prefixes::EXEC, &summary[..50.min(summary.len())])
                    } else {
                        format!("{} 🤔 Would you like to:\n   • Continue your previous session?\n   • Start a new session?\n   • Cancel?\n   Say 'continue', 'new', or 'no'", 
                            prefixes::EXEC)
                    };
                    self.append_output(clarification_msg);
                    
                    // Update pending state to show we've re-prompted
                    if let Some(ref mut p) = self.pending_executor {
                        p.is_initial_prompt = false;
                    }
                    
                    // Send re-prompt to mobile
                    let msg = serde_json::json!({
                        "type": "speak",
                        "text": "Would you like to continue your previous session or start a new one? Say continue, new, or no."
                    });
                    crate::relay_client::send_frame(msg.to_string());
                } else {
                    // Second ambiguous response - treat as unintelligible
                    self.handle_unintelligible_response();
                }
            }
            
            RouterAction::UnintelligibleResponse => {
                self.handle_unintelligible_response();
            }
            
            _ => {
                // Unexpected action in confirmation context
                self.append_output(format!("{} Unexpected response. Cancelling.", prefixes::EXEC));
                self.pending_executor = None;
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    fn handle_unintelligible_response(&mut self) {
        self.append_output(format!("{} 🤷 I didn't understand that.\n   Please say:\n   • 'continue' (or 'resume')\n   • 'new' (or 'fresh')\n   • 'no' (or 'cancel')", prefixes::EXEC));
        
        // Send clarification to mobile
        let msg = serde_json::json!({
            "type": "speak", 
            "text": "I didn't quite get that. Please say continue previous, start new, or no."
        });
        crate::relay_client::send_frame(msg.to_string());
        
        // Keep is_initial_prompt as false since we've already asked once
        if let Some(ref mut p) = self.pending_executor {
            p.is_initial_prompt = false;
        }
    }
    
    pub async fn launch_executor_with_action(&mut self, action: SessionAction) -> Result<()> {
        let pending = match self.pending_executor.take() {
            Some(p) => p,
            None => return Ok(()),
        };
        
        match action {
            SessionAction::ContinuePrevious => {
                // Launch with resume flag if we have a previous session
                if let Some(session_id) = self.last_completed_session_id.clone() {
                    self.launch_executor_with_resume(&pending.prompt, &session_id).await?;
                } else {
                    // No previous session to resume, start fresh
                    self.append_output(format!("{} No previous session found, starting fresh", prefixes::EXEC));
                    self.launch_executor(&pending.prompt).await?;
                }
            }
            SessionAction::StartNew => {
                // Launch fresh session
                self.launch_executor(&pending.prompt).await?;
            }
            SessionAction::Declined => {
                // Should not reach here, but handle gracefully
                self.mode = Mode::Idle;
                return Ok(());
            }
        }
        
        self.mode = Mode::ExecutorRunning;
        Ok(())
    }
}