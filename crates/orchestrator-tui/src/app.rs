// Compatibility wrapper to bridge UI components with TuiState
use crate::state::{TuiState, ScrollState};
use crate::types::{Mode, PendingExecutor, ErrorInfo, ScrollDirection};
use tokio::sync::mpsc;
use protocol::Message;

pub struct App {
    pub tui_state: TuiState,
    pub mode: Mode,
    pub pending_executor: Option<PendingExecutor>,
    pub error_info: Option<ErrorInfo>,
    pub output_lines: Vec<String>,
    pub log_lines: Vec<String>,
    pub input: String,
    pub show_help: bool,
    pub output: Vec<String>,
    pub scroll: ScrollState,
    pub core_in_tx: Option<mpsc::Sender<Message>>,
}

impl App {
    pub fn new(tui_state: TuiState) -> Self {
        Self {
            output: tui_state.output_buffer.clone(),
            scroll: tui_state.scroll.clone(),
            tui_state,
            mode: Mode::Idle,
            pending_executor: None,
            error_info: None,
            output_lines: Vec::new(),
            log_lines: Vec::new(),
            input: String::new(),
            show_help: false,
            core_in_tx: None,
        }
    }
    
    pub fn get_output_lines(&self) -> &[String] {
        &self.output_lines
    }
    
    pub fn get_log_lines(&self) -> &[String] {
        &self.log_lines
    }
    
    pub fn is_recording_mode(&self) -> bool {
        self.mode == Mode::Recording
    }
    
    pub fn handle_scroll(&mut self, direction: ScrollDirection) {
        match direction {
            ScrollDirection::Up => self.scroll.scroll_up(1),
            ScrollDirection::Down => self.scroll.scroll_down(1),
            ScrollDirection::PageUp => self.scroll.scroll_up(10),
            ScrollDirection::PageDown => self.scroll.scroll_down(10),
            ScrollDirection::Home | ScrollDirection::Top => {
                self.scroll.position = 0;
            },
            ScrollDirection::End | ScrollDirection::Bottom => {
                self.scroll.scroll_to_bottom();
            },
        }
    }
    
    pub fn dismiss_error(&mut self) {
        self.error_info = None;
        if self.mode == Mode::ShowingError {
            self.mode = Mode::Idle;
        }
    }
}