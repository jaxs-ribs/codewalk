#[cfg(feature = "tui-stt")]
use std::time::Instant;

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
#[derive(Debug, Clone, Copy)]
pub enum ScrollDirection {
    Up,
    Down,
    PageUp,
    PageDown,
    Home,
    End,
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
#[derive(Debug, Clone, PartialEq)]
pub enum Mode {
    Idle,
    #[cfg(feature = "tui-stt")]
    Recording,
    PlanPending,
    #[allow(dead_code)]
    Executing,  // Kept for potential future use
    ExecutorRunning,  // Generic executor running (Claude, Devin, etc.)
    ConfirmingExecutor,  // Waiting for user confirmation to launch executor
    ShowingError,  // Displaying error dialog
}

#[cfg(feature = "tui-stt")]
pub struct RecordingState {
    pub is_active: bool,
    pub started_at: Option<Instant>,
    pub blink_state: bool,
    pub last_blink: Instant,
}

#[cfg(feature = "tui-stt")]
impl RecordingState {
    pub fn new() -> Self {
        Self {
            is_active: false,
            started_at: None,
            blink_state: false,
            last_blink: Instant::now(),
        }
    }

    pub fn start(&mut self) {
        self.is_active = true;
        self.started_at = Some(Instant::now());
    }

    pub fn stop(&mut self) {
        self.is_active = false;
        self.started_at = None;
    }

    pub fn elapsed_seconds(&self) -> u64 {
        self.started_at
            .map(|start| start.elapsed().as_secs())
            .unwrap_or(0)
    }
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
pub struct PlanState {
    pub json: Option<String>,
    pub command: Option<String>,
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
#[derive(Debug, Clone)]
pub struct PendingExecutor {
    pub prompt: String,
    pub executor_name: String,
    pub working_dir: String,
    pub confirmation_id: Option<String>,
    pub is_initial_prompt: bool,  // true for first prompt, false for re-prompt
    pub session_action: Option<SessionAction>,  // What the user wants to do
}

#[derive(Debug, Clone, PartialEq)]
pub enum SessionAction {
    ContinuePrevious,
    StartNew,
    Declined,
}

impl PlanState {
    pub fn new() -> Self {
        Self {
            json: None,
            command: None,
        }
    }

    pub fn clear(&mut self) {
        self.json = None;
        self.command = None;
    }

    pub fn is_pending(&self) -> bool {
        self.json.is_some()
    }
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
#[derive(Debug, Clone)]
pub struct ErrorInfo {
    pub title: String,
    pub message: String,
    pub details: Option<String>,
}

impl ErrorInfo {
    pub fn new(title: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            message: message.into(),
            details: None,
        }
    }
    
    pub fn with_details(mut self, details: impl Into<String>) -> Self {
        self.details = Some(details.into());
        self
    }
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
pub struct ScrollState {
    pub offset: usize,
    pub auto_scroll: bool,
}

impl ScrollState {
    pub fn new() -> Self {
        Self {
            offset: 0,
            auto_scroll: true,
        }
    }
    
    pub fn scroll_up(&mut self, amount: usize) {
        self.offset = self.offset.saturating_sub(amount);
        self.auto_scroll = false;
    }
    
    pub fn scroll_down(&mut self, amount: usize, max: usize) {
        self.offset = std::cmp::min(self.offset + amount, max);
        // Re-enable auto-scroll if we're at the bottom
        if self.offset >= max {
            self.auto_scroll = true;
        }
    }
    
    pub fn scroll_to_bottom(&mut self, max: usize) {
        self.offset = max;
        self.auto_scroll = true;
    }
    
    pub fn page_up(&mut self, page_size: usize) {
        self.scroll_up(page_size);
    }
    
    pub fn page_down(&mut self, page_size: usize, max: usize) {
        self.scroll_down(page_size, max);
    }
}
