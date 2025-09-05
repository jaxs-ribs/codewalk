use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Core workstation state machine
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum WorkstationState {
    /// No active work
    Idle,
    
    /// Execution mode - running work
    Executing(ExecutionState),
    
    // Future modes:
    // Speccing(SpecState),
    // Inspecting(InspectionState),
}

/// States within execution mode
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ExecutionState {
    /// Waiting for user to confirm launching executor
    AwaitingConfirmation {
        prompt: String,
        confirmation_id: String,
        executor_type: String,
    },
    
    /// Executor is actively running
    Running {
        session_id: String,
        executor_type: String,
        prompt: String,
        started_at: std::time::SystemTime,
    },
    
    // Future states:
    // Interrupted { session_id: String, reason: String },
    // PhaseComplete { session_id: String, results: PhaseResults },
}

/// Events that can trigger state transitions
#[derive(Debug, Clone)]
pub enum StateEvent {
    // Execution events
    RequestExecution { prompt: String, executor_type: String },
    ConfirmExecution { confirmation_id: String },
    DeclineExecution { confirmation_id: String },
    ExecutionStarted { session_id: String },
    ExecutionCompleted { session_id: String },
    ExecutionFailed { session_id: String, error: String },
    
    // Future events:
    // RequestSpec { goal: String },
    // RequestInspection { session_id: String },
}

/// Result of a state transition
#[derive(Debug, Clone)]
pub enum TransitionResult {
    /// Transition succeeded, new state applied
    Success { old_state: WorkstationState, new_state: WorkstationState },
    
    /// Transition not valid from current state
    InvalidTransition { current_state: WorkstationState, event: String },
    
    /// Transition failed with error
    Error { message: String },
}

/// Manages the workstation state machine
pub struct StateManager {
    state: Arc<RwLock<WorkstationState>>,
    listeners: Arc<RwLock<Vec<Arc<dyn StateChangeListener + Send + Sync>>>>,
}

/// Trait for components that need to be notified of state changes
#[async_trait::async_trait]
pub trait StateChangeListener {
    async fn on_state_change(&self, old_state: &WorkstationState, new_state: &WorkstationState);
}

impl StateManager {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(WorkstationState::Idle)),
            listeners: Arc::new(RwLock::new(Vec::new())),
        }
    }
    
    /// Get current state
    pub async fn get_state(&self) -> WorkstationState {
        self.state.read().await.clone()
    }
    
    /// Register a state change listener
    pub async fn add_listener(&self, listener: Arc<dyn StateChangeListener + Send + Sync>) {
        self.listeners.write().await.push(listener);
    }
    
    /// Process an event and transition state if valid
    pub async fn handle_event(&self, event: StateEvent) -> TransitionResult {
        let mut state = self.state.write().await;
        let old_state = state.clone();
        
        let result = self.transition(&mut state, event);
        
        // If transition succeeded, notify listeners
        if let TransitionResult::Success { ref new_state, .. } = result {
            let listeners = self.listeners.read().await;
            for listener in listeners.iter() {
                listener.on_state_change(&old_state, new_state).await;
            }
        }
        
        result
    }
    
    /// Core state transition logic
    fn transition(&self, state: &mut WorkstationState, event: StateEvent) -> TransitionResult {
        match (state.clone(), event) {
            // From Idle
            (WorkstationState::Idle, StateEvent::RequestExecution { prompt, executor_type }) => {
                let confirmation_id = format!("confirm_{}", 
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis());
                
                let new_state = WorkstationState::Executing(ExecutionState::AwaitingConfirmation {
                    prompt,
                    confirmation_id,
                    executor_type,
                });
                
                let old = state.clone();
                *state = new_state.clone();
                
                TransitionResult::Success { old_state: old, new_state }
            }
            
            // From AwaitingConfirmation
            (WorkstationState::Executing(ExecutionState::AwaitingConfirmation { prompt, executor_type, confirmation_id }), 
             StateEvent::ConfirmExecution { confirmation_id: confirm_id }) => {
                if confirm_id != confirmation_id {
                    return TransitionResult::Error { 
                        message: format!("Confirmation ID mismatch: expected {}, got {}", confirmation_id, confirm_id) 
                    };
                }
                
                // Generate session ID
                let session_id = Self::generate_session_id();
                
                let new_state = WorkstationState::Executing(ExecutionState::Running {
                    session_id,
                    executor_type,
                    prompt,
                    started_at: std::time::SystemTime::now(),
                });
                
                let old = state.clone();
                *state = new_state.clone();
                
                TransitionResult::Success { old_state: old, new_state }
            }
            
            (WorkstationState::Executing(ExecutionState::AwaitingConfirmation { .. }), 
             StateEvent::DeclineExecution { .. }) => {
                let old = state.clone();
                *state = WorkstationState::Idle;
                
                TransitionResult::Success { old_state: old, new_state: WorkstationState::Idle }
            }
            
            // From Running
            (WorkstationState::Executing(ExecutionState::Running { .. }), 
             StateEvent::ExecutionCompleted { .. }) => {
                let old = state.clone();
                *state = WorkstationState::Idle;
                
                TransitionResult::Success { old_state: old, new_state: WorkstationState::Idle }
            }
            
            (WorkstationState::Executing(ExecutionState::Running { .. }), 
             StateEvent::ExecutionFailed { .. }) => {
                let old = state.clone();
                *state = WorkstationState::Idle;
                
                TransitionResult::Success { old_state: old, new_state: WorkstationState::Idle }
            }
            
            // Invalid transitions
            (current_state, event) => {
                TransitionResult::InvalidTransition { 
                    current_state, 
                    event: format!("{:?}", event) 
                }
            }
        }
    }
    
    fn generate_session_id() -> String {
        use chrono::Utc;
        let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
        let random_suffix: String = (0..6)
            .map(|_| {
                let n = rand::random::<u8>() % 36;
                if n < 10 {
                    (b'0' + n) as char
                } else {
                    (b'a' + n - 10) as char
                }
            })
            .collect();
        format!("{}_{}", timestamp, random_suffix)
    }
}

impl Default for StateManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_basic_execution_flow() {
        let manager = StateManager::new();
        
        // Should start in Idle
        assert_eq!(manager.get_state().await, WorkstationState::Idle);
        
        // Request execution
        let result = manager.handle_event(StateEvent::RequestExecution {
            prompt: "test prompt".to_string(),
            executor_type: "Claude".to_string(),
        }).await;
        
        assert!(matches!(result, TransitionResult::Success { .. }));
        assert!(matches!(
            manager.get_state().await,
            WorkstationState::Executing(ExecutionState::AwaitingConfirmation { .. })
        ));
        
        // Get confirmation ID
        let confirmation_id = if let WorkstationState::Executing(ExecutionState::AwaitingConfirmation { confirmation_id, .. }) = manager.get_state().await {
            confirmation_id
        } else {
            panic!("Expected AwaitingConfirmation state");
        };
        
        // Confirm execution
        let result = manager.handle_event(StateEvent::ConfirmExecution { confirmation_id }).await;
        assert!(matches!(result, TransitionResult::Success { .. }));
        assert!(matches!(
            manager.get_state().await,
            WorkstationState::Executing(ExecutionState::Running { .. })
        ));
        
        // Complete execution
        let result = manager.handle_event(StateEvent::ExecutionCompleted {
            session_id: "test".to_string(),
        }).await;
        assert!(matches!(result, TransitionResult::Success { .. }));
        assert_eq!(manager.get_state().await, WorkstationState::Idle);
    }
    
    #[tokio::test]
    async fn test_decline_execution() {
        let manager = StateManager::new();
        
        // Request execution
        manager.handle_event(StateEvent::RequestExecution {
            prompt: "test".to_string(),
            executor_type: "Claude".to_string(),
        }).await;
        
        // Decline
        let result = manager.handle_event(StateEvent::DeclineExecution {
            confirmation_id: "any".to_string(),
        }).await;
        
        assert!(matches!(result, TransitionResult::Success { .. }));
        assert_eq!(manager.get_state().await, WorkstationState::Idle);
    }
}