use orchestrator_core::state::{StateChangeListener, WorkstationState, ExecutionState};

/// Bridges core state changes to TUI
pub struct TUIStateObserver {
    state_tx: tokio::sync::mpsc::Sender<StateUpdate>,
}

#[derive(Debug, Clone)]
pub enum StateUpdate {
    StateChanged { 
        old_state: WorkstationState, 
        new_state: WorkstationState 
    },
}

impl TUIStateObserver {
    pub fn new(state_tx: tokio::sync::mpsc::Sender<StateUpdate>) -> Self {
        Self { state_tx }
    }
}

#[async_trait::async_trait]
impl StateChangeListener for TUIStateObserver {
    async fn on_state_change(&self, old_state: &WorkstationState, new_state: &WorkstationState) {
        let _ = self.state_tx.send(StateUpdate::StateChanged {
            old_state: old_state.clone(),
            new_state: new_state.clone(),
        }).await;
    }
}

/// Helper to map core state to TUI display needs
pub fn map_core_state_to_ui(state: &WorkstationState) -> TUIStateInfo {
    match state {
        WorkstationState::Idle => TUIStateInfo {
            is_executor_running: false,
            is_awaiting_confirmation: false,
            session_id: None,
            prompt: None,
        },
        WorkstationState::Executing(exec_state) => match exec_state {
            ExecutionState::AwaitingConfirmation { prompt, .. } => TUIStateInfo {
                is_executor_running: false,
                is_awaiting_confirmation: true,
                session_id: None,
                prompt: Some(prompt.clone()),
            },
            ExecutionState::Running { session_id, prompt, .. } => TUIStateInfo {
                is_executor_running: true,
                is_awaiting_confirmation: false,
                session_id: Some(session_id.clone()),
                prompt: Some(prompt.clone()),
            },
        },
    }
}

#[derive(Debug, Clone)]
pub struct TUIStateInfo {
    pub is_executor_running: bool,
    pub is_awaiting_confirmation: bool,
    pub session_id: Option<String>,
    pub prompt: Option<String>,
}