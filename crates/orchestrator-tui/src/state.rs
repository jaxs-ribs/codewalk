use tokio::sync::mpsc;
use protocol::Message;
use std::collections::VecDeque;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Tab {
    Output,
    Logs,
}

#[derive(Debug)]
pub struct ScrollState {
    pub position: usize,
    pub max_position: usize,
}

impl ScrollState {
    pub fn new() -> Self {
        Self {
            position: 0,
            max_position: 0,
        }
    }

    pub fn reset(&mut self) {
        self.position = 0;
        self.max_position = 0;
    }

    pub fn scroll_up(&mut self, amount: usize) {
        self.position = self.position.saturating_sub(amount);
    }

    pub fn scroll_down(&mut self, amount: usize) {
        self.position = (self.position + amount).min(self.max_position);
    }

    pub fn scroll_to_bottom(&mut self) {
        self.position = self.max_position;
    }

    pub fn update_max(&mut self, content_lines: usize, viewport_height: usize) {
        if content_lines > viewport_height {
            self.max_position = content_lines - viewport_height;
            // Auto-adjust position if we're beyond the new max
            if self.position > self.max_position {
                self.position = self.max_position;
            }
        } else {
            self.max_position = 0;
            self.position = 0;
        }
    }
}

/// UI-only state that doesn't affect business logic
pub struct TuiState {
    pub output_buffer: Vec<String>,
    pub log_buffer: VecDeque<String>,
    pub input_buffer: String,
    pub scroll: ScrollState,
    pub log_scroll: ScrollState,
    pub selected_tab: Tab,
    pub show_help: bool,
    pub error_message: Option<ErrorDisplay>,
    
    // Channel to send messages to the core
    tx: mpsc::Sender<Message>,
}

#[derive(Debug, Clone)]
pub struct ErrorDisplay {
    pub title: String,
    pub message: String,
    pub details: String,
}

impl TuiState {
    pub fn new(tx: mpsc::Sender<Message>) -> Self {
        Self {
            output_buffer: Vec::new(),
            log_buffer: VecDeque::with_capacity(1000),
            input_buffer: String::new(),
            scroll: ScrollState::new(),
            log_scroll: ScrollState::new(),
            selected_tab: Tab::Output,
            show_help: false,
            error_message: None,
            tx,
        }
    }

    pub fn append_output(&mut self, text: String) {
        self.output_buffer.push(text);
        // Auto-scroll to bottom when new output arrives
        self.scroll.scroll_to_bottom();
    }

    pub fn append_log(&mut self, text: String) {
        // Keep log buffer bounded
        if self.log_buffer.len() >= 1000 {
            self.log_buffer.pop_front();
        }
        self.log_buffer.push_back(text);
    }

    pub fn clear_output(&mut self) {
        self.output_buffer.clear();
        self.scroll.reset();
    }

    pub fn clear_logs(&mut self) {
        self.log_buffer.clear();
        self.log_scroll.reset();
    }

    pub fn show_error(&mut self, title: String, message: String, details: String) {
        self.error_message = Some(ErrorDisplay {
            title,
            message,
            details,
        });
    }

    pub fn dismiss_error(&mut self) {
        self.error_message = None;
    }

    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    pub fn switch_tab(&mut self, tab: Tab) {
        self.selected_tab = tab;
    }

    pub fn next_tab(&mut self) {
        self.selected_tab = match self.selected_tab {
            Tab::Output => Tab::Logs,
            Tab::Logs => Tab::Output,
        };
    }

    pub fn prev_tab(&mut self) {
        self.next_tab(); // With only 2 tabs, prev is same as next
    }

    pub async fn send_user_text(&self, text: String) -> anyhow::Result<()> {
        let msg = Message::user_text(text, Some("tui".to_string()), true);
        self.tx.send(msg).await.map_err(|e| anyhow::anyhow!("Failed to send: {}", e))
    }

    pub fn can_edit_input(&self) -> bool {
        self.error_message.is_none() && !self.show_help
    }

    pub fn handle_input_char(&mut self, c: char) {
        if self.can_edit_input() {
            self.input_buffer.push(c);
        }
    }

    pub fn handle_backspace(&mut self) {
        if self.can_edit_input() {
            self.input_buffer.pop();
        }
    }

    pub fn clear_input(&mut self) {
        self.input_buffer.clear();
    }

    pub fn take_input(&mut self) -> String {
        let input = self.input_buffer.clone();
        self.input_buffer.clear();
        input
    }
}