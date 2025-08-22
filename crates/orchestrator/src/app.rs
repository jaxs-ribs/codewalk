use anyhow::Result;
use std::time::Duration;

use crate::backend;
use crate::constants::{self, messages, prefixes};
use crate::executor::{ExecutorSession, ExecutorFactory, ExecutorType, ExecutorConfig, ExecutorOutput};
use crate::settings::AppSettings;
use crate::types::{Mode, PlanState, RecordingState, PendingExecutor, ErrorInfo, ScrollState, ScrollDirection};
use crate::utils::TextWrapper;
use crate::log_monitor::{ParsedLogLine, spawn_log_monitor, LogType};
use router::RouterAction;
use tokio::sync::mpsc;

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    pub recording: RecordingState,
    pub executor_session: Option<Box<dyn ExecutorSession>>,
    pub current_executor: ExecutorType,
    pub settings: AppSettings,
    pub pending_executor: Option<PendingExecutor>,
    pub error_info: Option<ErrorInfo>,
    pub scroll: ScrollState,
    pub session_logs: Vec<ParsedLogLine>,
    pub log_scroll: ScrollState,
    pub log_receiver: Option<mpsc::Receiver<ParsedLogLine>>,
}

impl App {
    pub fn new() -> Self {
        let settings = AppSettings::load();
        Self {
            output: Vec::new(),
            input: String::new(),
            mode: Mode::Idle,
            plan: PlanState::new(),
            recording: RecordingState::new(),
            executor_session: None,
            current_executor: ExecutorFactory::default_executor(),
            settings,
            pending_executor: None,
            error_info: None,
            scroll: ScrollState::new(),
            session_logs: Vec::new(),
            log_scroll: ScrollState::new(),
            log_receiver: None,
        }
    }
    
    /// Clean up any running executor sessions before exit
    pub async fn cleanup(&mut self) {
        if let Some(mut session) = self.executor_session.take() {
            let _ = session.terminate().await;
        }
    }

    pub fn append_output(&mut self, line: String) {
        // Wrap long lines before adding to output
        let wrapped = TextWrapper::wrap_line(&line);
        for wrapped_line in wrapped {
            self.output.push(wrapped_line);
            self.trim_output();
        }
        // Auto-scroll to bottom if enabled
        if self.scroll.auto_scroll {
            self.scroll.scroll_to_bottom(self.get_max_scroll());
        }
    }

    fn trim_output(&mut self) {
        if self.output.len() > constants::MAX_OUTPUT_LINES {
            self.output.remove(0);
            // Adjust scroll offset if we removed a line
            if self.scroll.offset > 0 {
                self.scroll.offset = self.scroll.offset.saturating_sub(1);
            }
        }
    }
    
    pub fn show_error(&mut self, title: impl Into<String>, message: impl Into<String>) {
        self.error_info = Some(ErrorInfo::new(title, message));
        self.mode = Mode::ShowingError;
    }
    
    pub fn show_error_with_details(&mut self, title: impl Into<String>, message: impl Into<String>, details: impl Into<String>) {
        self.error_info = Some(ErrorInfo::new(title, message).with_details(details));
        self.mode = Mode::ShowingError;
    }
    
    pub fn dismiss_error(&mut self) {
        self.error_info = None;
        self.mode = Mode::Idle;
    }
    
    pub fn get_max_scroll(&self) -> usize {
        self.output.len().saturating_sub(1)
    }
    
    pub fn handle_scroll(&mut self, direction: ScrollDirection, amount: usize) {
        let max = self.get_max_scroll();
        match direction {
            ScrollDirection::Up => self.scroll.scroll_up(amount),
            ScrollDirection::Down => self.scroll.scroll_down(amount, max),
            ScrollDirection::PageUp => self.scroll.page_up(amount),
            ScrollDirection::PageDown => self.scroll.page_down(amount, max),
            ScrollDirection::Home => self.scroll.offset = 0,
            ScrollDirection::End => self.scroll.scroll_to_bottom(max),
        }
    }

    pub async fn start_recording(&mut self) -> Result<()> {
        self.mode = Mode::Recording;
        self.recording.start();
        
        if let Err(e) = backend::record_voice(true).await {
            self.recording.stop();
            self.show_error_with_details(
                "Recording Failed",
                "Failed to start audio recording",
                format!("Error: {}", e)
            );
            return Err(e);
        }
        
        self.append_output(format!("{} Recording started...", prefixes::ASR));
        Ok(())
    }

    pub async fn stop_recording(&mut self) -> Result<()> {
        if let Err(e) = backend::record_voice(false).await {
            self.recording.stop();
            self.show_error_with_details(
                "Recording Failed", 
                "Failed to stop audio recording",
                format!("Error: {}", e)
            );
            return Err(e);
        }
        
        let audio = match backend::take_recorded_audio().await {
            Ok(audio) => audio,
            Err(e) => {
                self.recording.stop();
                self.show_error_with_details(
                    "Audio Processing Failed",
                    "Failed to retrieve recorded audio",
                    format!("Error: {}", e)
                );
                return Err(e);
            }
        };
        
        if audio.is_empty() {
            self.handle_empty_recording();
        } else {
            self.append_output(format!("{} Processing audio...", prefixes::ASR));
            if let Err(e) = self.process_audio(audio).await {
                self.show_error_with_details(
                    "Transcription Failed",
                    "Failed to process audio",
                    format!("Error: {}", e)
                );
            }
        }
        
        self.recording.stop();
        Ok(())
    }

    fn handle_empty_recording(&mut self) {
        self.append_output(format!("{} {}", prefixes::ASR, messages::NO_AUDIO));
        self.mode = Mode::Idle;
    }

    async fn process_audio(&mut self, audio: Vec<u8>) -> Result<()> {
        let utterance = backend::voice_to_text(audio).await?;
        if !utterance.trim().is_empty() {
            self.append_output(format!("{} Transcribed: {}", prefixes::ASR, utterance));
            // Send to LLM router
            self.route_command(&utterance).await?;
            // If we're not in a special mode after routing, go back to idle
            if self.mode == Mode::Recording {
                self.mode = Mode::Idle;
            }
        } else {
            self.append_output(format!("{} No speech detected", prefixes::ASR));
            self.mode = Mode::Idle;
        }
        Ok(())
    }


    pub fn cancel_current_operation(&mut self) {
        match self.mode {
            Mode::PlanPending => {
                self.append_output(format!("{} {}", prefixes::PLAN, messages::PLAN_CANCELED));
                self.plan.clear();
                self.mode = Mode::Idle;
            }
            Mode::Recording => {
                // Stop backend recording first
                let _ = tokio::task::block_in_place(|| {
                    tokio::runtime::Handle::current().block_on(backend::record_voice(false))
                });
                self.recording.stop();
                self.mode = Mode::Idle;
                self.append_output(format!("{} Recording cancelled", prefixes::ASR));
            }
            Mode::ExecutorRunning => {
                if let Some(mut session) = self.executor_session.take() {
                    // Try to terminate executor gracefully
                    let _ = tokio::task::block_in_place(|| {
                        tokio::runtime::Handle::current().block_on(session.terminate())
                    });
                    self.append_output(format!("{} Executor session terminated by user", prefixes::EXEC));
                }
                self.mode = Mode::Idle;
            }
            Mode::ConfirmingExecutor => {
                self.cancel_executor_confirmation();
            }
            Mode::ShowingError => {
                self.dismiss_error();
            }
            _ => {}
        }
    }

    async fn route_command(&mut self, text: &str) -> Result<()> {
        self.append_output(format!("{} Routing command...", prefixes::PLAN));
        
        // Get router response from LLM
        let response_json = match backend::text_to_llm_cmd(text).await {
            Ok(json) => json,
            Err(e) => {
                self.show_error_with_details(
                    "LLM Routing Failed",
                    "Failed to process command through LLM",
                    format!("Error: {}", e)
                );
                self.mode = Mode::Idle;
                return Err(e);
            }
        };
        
        let response = match backend::parse_router_response(&response_json).await {
            Ok(r) => r,
            Err(e) => {
                self.show_error_with_details(
                    "Response Parsing Failed",
                    "Failed to parse LLM response",
                    format!("Response: {}\nError: {}", response_json, e)
                );
                self.mode = Mode::Idle;
                return Err(e);
            }
        };
        
        match response.action {
            RouterAction::LaunchClaude => {
                if let Some(prompt) = response.prompt {
                    if self.settings.require_executor_confirmation {
                        // Store pending executor info and switch to confirmation mode
                        let config = ExecutorConfig::default();
                        self.pending_executor = Some(PendingExecutor {
                            prompt: prompt.clone(),
                            executor_name: self.current_executor.name().to_string(),
                            working_dir: config.working_dir.to_string_lossy().to_string(),
                        });
                        self.mode = Mode::ConfirmingExecutor;
                        self.append_output(format!("{} Ready to launch {}. Press Enter to confirm, Escape to cancel.", 
                                                 prefixes::PLAN, self.current_executor.name()));
                    } else {
                        // Launch immediately without confirmation
                        self.append_output(format!("{} Launching {} with: {}", prefixes::EXEC, self.current_executor.name(), prompt));
                        self.launch_executor(&prompt).await?;
                    }
                } else {
                    self.append_output(format!("{} Error: No prompt extracted", prefixes::PLAN));
                    self.mode = Mode::Idle;
                }
            }
            RouterAction::CannotParse => {
                let reason = response.reason.unwrap_or_else(|| "Could not understand command".to_string());
                self.append_output(format!("{} {}", prefixes::PLAN, reason));
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    async fn launch_executor(&mut self, prompt: &str) -> Result<()> {
        self.append_output(format!("{} Starting {}...", prefixes::EXEC, self.current_executor.name()));
        
        let config = ExecutorConfig::default();
        match ExecutorFactory::create(self.current_executor.clone(), prompt, Some(config.clone())).await {
            Ok(session) => {
                self.executor_session = Some(session);
                self.mode = Mode::ExecutorRunning;
                self.append_output(format!("{} {} session started", prefixes::EXEC, self.current_executor.name()));
                self.append_output(format!("Working directory: {:?}", config.working_dir));
                self.append_output(format!("Prompt: {}", prompt));
                
                // Start log monitoring for this session
                self.start_log_monitoring(Some(&config.working_dir));
                
                // Don't block here - output will be polled in main loop
            }
            Err(e) => {
                if e.to_string().contains("No such file or directory") || e.to_string().contains("not found") {
                    self.append_output(format!("{} {} not found. Please install it first.", prefixes::PLAN, self.current_executor.name()));
                } else {
                    self.append_output(format!("{} Failed to launch {}: {}", prefixes::PLAN, self.current_executor.name(), e));
                }
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    pub async fn poll_executor_output(&mut self) -> Result<()> {
        let mut session_ended = false;
        let mut outputs = Vec::new();
        
        if let Some(session) = &mut self.executor_session {
            // Read up to 10 outputs per poll to avoid blocking
            for _ in 0..10 {
                match session.read_output().await {
                    Ok(Some(output)) => outputs.push(output),
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
            
            // Check if process is still running
            if !session.is_running() {
                session_ended = true;
            }
        }
        
        // Display outputs based on type
        for output in outputs {
            match output {
                ExecutorOutput::Stdout(line) => {
                    // Try to parse as streaming JSON from Claude
                    if let Some(log_entry) = self.parse_claude_json(&line) {
                        self.session_logs.push(log_entry);
                        // Auto-scroll logs if enabled
                        if self.log_scroll.auto_scroll {
                            self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
                        }
                    } else {
                        // Fallback to regular output display
                        self.append_output(format!("{}: {}", self.current_executor.name(), line));
                    }
                }
                ExecutorOutput::Stderr(line) => {
                    self.append_output(format!("{} {} error: {}", prefixes::WARN, self.current_executor.name(), line));
                }
                ExecutorOutput::Status(status) => {
                    self.append_output(format!("{} Status: {}", prefixes::EXEC, status));
                }
                ExecutorOutput::Progress(pct, msg) => {
                    self.append_output(format!("{} Progress: {:.0}% - {}", prefixes::EXEC, pct * 100.0, msg));
                }
            }
        }
        
        if session_ended {
            self.append_output(format!("{} {} session completed", prefixes::EXEC, self.current_executor.name()));
            self.executor_session = None;
            self.mode = Mode::Idle;
        }
        
        Ok(())
    }
    
    pub async fn handle_text_input(&mut self) -> Result<()> {
        if !self.input.is_empty() {
            let text = self.input.clone();
            self.append_output(format!("{} {}", prefixes::UTTERANCE, text));
            self.input.clear();
            // Route through LLM instead of old plan system
            self.route_command(&text).await?;
        }
        Ok(())
    }

    pub fn update_blink(&mut self) {
        if self.recording.last_blink.elapsed() > Duration::from_millis(constants::BLINK_INTERVAL_MS) {
            self.recording.blink_state = !self.recording.blink_state;
            self.recording.last_blink = std::time::Instant::now();
        }
    }

    pub fn get_recording_time(&self) -> String {
        let elapsed = self.recording.elapsed_seconds();
        format!("{:02}:{:02}", elapsed / 60, elapsed % 60)
    }

    pub fn can_edit_input(&self) -> bool {
        self.mode == Mode::Idle
    }

    pub fn can_start_recording(&self) -> bool {
        self.mode == Mode::Idle && !self.recording.is_active
    }

    pub fn can_stop_recording(&self) -> bool {
        self.mode == Mode::Recording && self.recording.is_active
    }

    pub async fn confirm_executor(&mut self) -> Result<()> {
        if let Some(pending) = self.pending_executor.take() {
            self.append_output(format!("{} Confirmed. Launching {}...", prefixes::EXEC, pending.executor_name));
            self.mode = Mode::Idle;  // Reset mode before launching
            self.launch_executor(&pending.prompt).await?;
        }
        Ok(())
    }
    
    pub fn cancel_executor_confirmation(&mut self) {
        if self.mode == Mode::ConfirmingExecutor {
            self.pending_executor = None;
            self.mode = Mode::Idle;
            self.append_output(format!("{} Executor launch cancelled", prefixes::PLAN));
        }
    }
    
    /// Toggle executor confirmation requirement (for testing)
    #[allow(dead_code)]
    pub fn toggle_confirmation(&mut self) {
        self.settings.require_executor_confirmation = !self.settings.require_executor_confirmation;
        let status = if self.settings.require_executor_confirmation { "ON" } else { "OFF" };
        self.append_output(format!("{} Executor confirmation is now {}", prefixes::EXEC, status));
    }
    
    pub fn can_cancel(&self) -> bool {
        matches!(self.mode, Mode::Recording | Mode::PlanPending | Mode::ExecutorRunning | Mode::ConfirmingExecutor | Mode::ShowingError)
    }
    
    /// Start monitoring log files for the current session
    pub fn start_log_monitoring(&mut self, working_dir: Option<&std::path::Path>) {
        // Clear previous logs
        self.session_logs.clear();
        self.log_scroll = ScrollState::new();
        
        // Start new monitor
        let receiver = spawn_log_monitor(working_dir);
        self.log_receiver = Some(receiver);
    }
    
    /// Parse Claude's streaming JSON output
    fn parse_claude_json(&self, line: &str) -> Option<ParsedLogLine> {
        // Try to parse the line as JSON
        if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(line) {
            // Extract type field
            let entry_type = json_value.get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            
            // Determine log type with improved detection
            let log_type = match entry_type {
                "message" | "message_start" => {
                    // Check role to determine if user or assistant
                    let role = json_value.get("message")
                        .and_then(|m| m.get("role"))
                        .and_then(|r| r.as_str())
                        .or_else(|| json_value.get("role").and_then(|r| r.as_str()));
                    
                    match role {
                        Some("user") => crate::log_monitor::LogType::UserMessage,
                        Some("assistant") => crate::log_monitor::LogType::AssistantMessage,
                        Some("system") => crate::log_monitor::LogType::Status,
                        _ => crate::log_monitor::LogType::Unknown,
                    }
                }
                "content_block_start" | "content_block_delta" | "text" => {
                    // These are typically assistant content
                    crate::log_monitor::LogType::AssistantMessage
                }
                "tool_use" | "tool_call" => crate::log_monitor::LogType::ToolCall,
                "tool_result" | "tool_response" => crate::log_monitor::LogType::ToolResult,
                "error" => crate::log_monitor::LogType::Error,
                "status" | "ping" | "message_stop" => crate::log_monitor::LogType::Status,
                _ => {
                    // Fallback: check for role field directly
                    if let Some(role) = json_value.get("role").and_then(|r| r.as_str()) {
                        match role {
                            "user" => crate::log_monitor::LogType::UserMessage,
                            "assistant" => crate::log_monitor::LogType::AssistantMessage,
                            "system" => crate::log_monitor::LogType::Status,
                            _ => crate::log_monitor::LogType::Unknown,
                        }
                    } else {
                        crate::log_monitor::LogType::Unknown
                    }
                }
            };
            
            // Extract content with better handling
            let content = self.extract_json_content(&json_value);
            
            return Some(ParsedLogLine {
                timestamp: std::time::SystemTime::now(),
                entry_type: log_type,
                content,
                raw: line.to_string(),
            });
        }
        
        None
    }
    
    /// Extract human-readable content from JSON
    fn extract_json_content(&self, json: &serde_json::Value) -> String {
        // Try to get message content
        if let Some(message) = json.get("message") {
            if let Some(content) = message.get("content") {
                if let Some(text) = content.as_str() {
                    return text.to_string();
                }
                // Handle content array (Claude often uses content array with text blocks)
                if let Some(arr) = content.as_array() {
                    let texts: Vec<String> = arr.iter()
                        .filter_map(|item| {
                            item.get("text")
                                .and_then(|t| t.as_str())
                                .map(|s| s.to_string())
                        })
                        .collect();
                    if !texts.is_empty() {
                        return texts.join(" ");
                    }
                }
            }
        }
        
        // Try content_block for streaming content
        if let Some(content_block) = json.get("content_block") {
            if let Some(text) = content_block.get("text").and_then(|t| t.as_str()) {
                return text.to_string();
            }
        }
        
        // Try delta for streaming updates
        if let Some(delta) = json.get("delta") {
            if let Some(text) = delta.get("text").and_then(|t| t.as_str()) {
                return text.to_string();
            }
        }
        
        // Try tool information
        if let Some(tool_name) = json.get("name").and_then(|n| n.as_str()) {
            // Try to get tool input for more context
            if let Some(input) = json.get("input") {
                if let Some(file_path) = input.get("file_path").and_then(|f| f.as_str()) {
                    return format!("{}: {}", tool_name, file_path);
                }
                return format!("{}", tool_name);
            }
            return format!("{}", tool_name);
        }
        
        // Try tool result output
        if let Some(output) = json.get("output").and_then(|o| o.as_str()) {
            // Truncate long outputs
            if output.len() > 50 {
                return format!("{}...", &output[..47]);
            }
            return output.to_string();
        }
        
        // Try to get text field directly
        if let Some(text) = json.get("text").and_then(|t| t.as_str()) {
            return text.to_string();
        }
        
        // Try to get type as fallback
        if let Some(typ) = json.get("type").and_then(|t| t.as_str()) {
            // Don't show certain verbose types
            if matches!(typ, "ping" | "message_start" | "message_stop" | "content_block_start" | "content_block_stop") {
                return format!("[{}]", typ);
            }
            return format!("[{}]", typ);
        }
        
        // Try to get result field for tool results
        if let Some(result) = json.get("result").and_then(|r| r.as_str()) {
            return result.to_string();
        }
        
        // Last resort - show type field or unknown
        "[...]".to_string()
    }
    
    /// Poll for new log entries
    pub async fn poll_logs(&mut self) -> Result<()> {
        if let Some(receiver) = &mut self.log_receiver {
            // Try to receive up to 10 log entries without blocking
            for _ in 0..10 {
                match receiver.try_recv() {
                    Ok(log) => {
                        self.session_logs.push(log);
                        // Auto-scroll logs if enabled
                        if self.log_scroll.auto_scroll {
                            self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
                        }
                    }
                    Err(mpsc::error::TryRecvError::Empty) => break,
                    Err(mpsc::error::TryRecvError::Disconnected) => {
                        self.log_receiver = None;
                        break;
                    }
                }
            }
            
            // Trim logs if too many
            const MAX_LOGS: usize = 1000;
            if self.session_logs.len() > MAX_LOGS {
                let remove_count = self.session_logs.len() - MAX_LOGS;
                self.session_logs.drain(0..remove_count);
                // Adjust scroll offset
                if self.log_scroll.offset >= remove_count {
                    self.log_scroll.offset -= remove_count;
                } else {
                    self.log_scroll.offset = 0;
                }
            }
        }
        Ok(())
    }
}