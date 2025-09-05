use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ScrollDirection {
    Up,
    Down,
    Top,
    Bottom,
    PageUp,
    PageDown,
    Home,
    End,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Mode {
    Idle,
    Recording,
    PlanPending,
    Executing,
    ExecutorRunning,
    ConfirmingExecutor,
    ShowingError,
}

impl Default for Mode {
    fn default() -> Self {
        Mode::Idle
    }
}

#[derive(Debug, Clone)]
pub struct PendingExecutor {
    pub prompt: String,
    pub executor_name: String,
    pub working_dir: String,
    pub confirmation_id: Option<String>,
    pub is_initial_prompt: bool,
    pub session_action: Option<SessionAction>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SessionAction {
    StartNew,
    Continue,
    Replace,
}

#[derive(Debug, Clone)]
pub struct ErrorInfo {
    pub title: String,
    pub message: String,
    pub is_retryable: bool,
}