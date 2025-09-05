use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    Idle,
    Running,
    Paused,
    Completed,
    Failed(SessionFailureReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionFailureReason {
    UserCancelled,
    ExecutorCrashed,
    NetworkError,
    Timeout,
    Unknown,
}

impl fmt::Display for SessionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SessionState::Idle => write!(f, "Idle"),
            SessionState::Running => write!(f, "Running"),
            SessionState::Paused => write!(f, "Paused"),
            SessionState::Completed => write!(f, "Completed"),
            SessionState::Failed(reason) => write!(f, "Failed: {}", reason),
        }
    }
}

impl fmt::Display for SessionFailureReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SessionFailureReason::UserCancelled => write!(f, "User cancelled"),
            SessionFailureReason::ExecutorCrashed => write!(f, "Executor crashed"),
            SessionFailureReason::NetworkError => write!(f, "Network error"),
            SessionFailureReason::Timeout => write!(f, "Timeout"),
            SessionFailureReason::Unknown => write!(f, "Unknown error"),
        }
    }
}

pub struct SessionStateMachine {
    current_state: SessionState,
}

impl SessionStateMachine {
    pub fn new() -> Self {
        Self {
            current_state: SessionState::Idle,
        }
    }

    pub fn current_state(&self) -> SessionState {
        self.current_state
    }

    pub fn can_transition_to(&self, new_state: SessionState) -> bool {
        match (self.current_state, new_state) {
            (SessionState::Idle, SessionState::Running) => true,
            (SessionState::Running, SessionState::Paused) => true,
            (SessionState::Running, SessionState::Completed) => true,
            (SessionState::Running, SessionState::Failed(_)) => true,
            (SessionState::Paused, SessionState::Running) => true,
            (SessionState::Paused, SessionState::Completed) => true,
            (SessionState::Paused, SessionState::Failed(_)) => true,
            _ => false,
        }
    }

    pub fn transition_to(&mut self, new_state: SessionState) -> Result<(), String> {
        if self.can_transition_to(new_state) {
            self.current_state = new_state;
            Ok(())
        } else {
            Err(format!(
                "Invalid state transition from {} to {}",
                self.current_state, new_state
            ))
        }
    }

    pub fn start(&mut self) -> Result<(), String> {
        self.transition_to(SessionState::Running)
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.transition_to(SessionState::Paused)
    }

    pub fn resume(&mut self) -> Result<(), String> {
        if self.current_state == SessionState::Paused {
            self.transition_to(SessionState::Running)
        } else {
            Err(format!("Cannot resume from state: {}", self.current_state))
        }
    }

    pub fn complete(&mut self) -> Result<(), String> {
        self.transition_to(SessionState::Completed)
    }

    pub fn fail(&mut self, reason: SessionFailureReason) -> Result<(), String> {
        self.transition_to(SessionState::Failed(reason))
    }

    pub fn reset(&mut self) {
        self.current_state = SessionState::Idle;
    }
}

impl Default for SessionStateMachine {
    fn default() -> Self {
        Self::new()
    }
}