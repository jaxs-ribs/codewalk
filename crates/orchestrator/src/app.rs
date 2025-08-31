use anyhow::Result;
#[cfg(feature = "tui-stt")]
use std::time::Duration;

use crate::backend;
use crate::constants::{self, messages, prefixes};
use crate::relay_client::{self, RelayEvent};
use control_center::{ExecutorConfig, ExecutorOutput};
use control_center::center::ControlCenter;
use crate::settings::AppSettings;
use crate::types::{Mode, PlanState, PendingExecutor, ErrorInfo, ScrollState, ScrollDirection};
#[cfg(feature = "tui-stt")]
use crate::types::RecordingState;
use crate::utils::TextWrapper;
use control_center::ParsedLogLine;
use router::RouterAction;
 

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    #[cfg(feature = "tui-stt")]
    pub recording: RecordingState,
    pub center: ControlCenter,
    pub settings: AppSettings,
    pub pending_executor: Option<PendingExecutor>,
    pub error_info: Option<ErrorInfo>,
    pub scroll: ScrollState,
    pub session_logs: Vec<ParsedLogLine>,
    pub log_scroll: ScrollState,
    pub relay_rx: Option<tokio::sync::mpsc::Receiver<RelayEvent>>,
    pub core_in_tx: Option<tokio::sync::mpsc::Sender<protocol::Message>>,
    pub core_out_rx: Option<tokio::sync::mpsc::Receiver<protocol::Message>>,
    pub cmd_tx: tokio::sync::mpsc::Sender<crate::core_bridge::AppCommand>,
    pub cmd_rx: tokio::sync::mpsc::Receiver<crate::core_bridge::AppCommand>,
    // No direct receiver; logs are pulled via ControlCenter
}

impl App {
    pub fn new() -> Self {
        let settings = AppSettings::load();
        let (cmd_tx, cmd_rx) = tokio::sync::mpsc::channel(100);
        Self {
            output: Vec::new(),
            input: String::new(),
            mode: Mode::Idle,
            plan: PlanState::new(),
            #[cfg(feature = "tui-stt")]
            recording: RecordingState::new(),
            center: ControlCenter::new(),
            settings,
            pending_executor: None,
            error_info: None,
            scroll: ScrollState::new(),
            session_logs: Vec::new(),
            log_scroll: ScrollState::new(),
            relay_rx: None,
            core_in_tx: None,
            core_out_rx: None,
            cmd_tx,
            cmd_rx,
        }
    }
    
    /// Clean up any running executor sessions before exit
    pub async fn cleanup(&mut self) {
        let _ = self.center.terminate().await;
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
    
    #[allow(dead_code)]
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

    #[cfg(feature = "tui-stt")]
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

    #[cfg(feature = "tui-stt")]
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

    #[cfg(feature = "tui-stt")]
    fn handle_empty_recording(&mut self) {
        self.append_output(format!("{} {}", prefixes::ASR, messages::NO_AUDIO));
        self.mode = Mode::Idle;
    }

    #[cfg(feature = "tui-stt")]
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
            #[cfg(feature = "tui-stt")]
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
                // Try to terminate executor gracefully
                let _ = tokio::task::block_in_place(|| {
                    tokio::runtime::Handle::current().block_on(self.center.terminate())
                });
                self.append_output(format!("{} Executor session terminated by user", prefixes::EXEC));
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
                            executor_name: self.center.executor.name().to_string(),
                            working_dir: config.working_dir.to_string_lossy().to_string(),
                        });
                        self.mode = Mode::ConfirmingExecutor;
                        self.append_output(format!("{} Ready to launch {}. Press Enter to confirm, Escape to cancel.", 
                                                 prefixes::PLAN, self.center.executor.name()));
                    } else {
                        // Launch immediately without confirmation
                        self.append_output(format!("{} Launching {} with: {}", prefixes::EXEC, self.center.executor.name(), prompt));
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
        self.append_output(format!("{} Starting {}...", prefixes::EXEC, self.center.executor.name()));

        let config = ExecutorConfig::default();
        match self.center.launch(prompt, Some(config.clone())).await {
            Ok(()) => {
                self.mode = Mode::ExecutorRunning;
                self.append_output(format!("{} {} session started", prefixes::EXEC, self.center.executor.name()));
                self.append_output(format!("Working directory: {:?}", config.working_dir));
                self.append_output(format!("Prompt: {}", prompt));
            }
            Err(e) => {
                if e.to_string().contains("No such file or directory") || e.to_string().contains("not found") {
                    self.append_output(format!("{} {} not found. Please install it first.", prefixes::PLAN, self.center.executor.name()));
                } else {
                    self.append_output(format!("{} Failed to launch {}: {}", prefixes::PLAN, self.center.executor.name(), e));
                }
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    pub async fn poll_executor_output(&mut self) -> Result<()> {
        let outputs = self.center.poll_executor_output(10).await;
        let session_ended = !self.center.is_running();
        
        // Display outputs based on type
        for output in outputs {
            match output {
                ExecutorOutput::Stdout(line) => {
                    // Structured logs are handled by log monitor. Echo line for context.
                    self.append_output(format!("{}: {}", self.center.executor.name(), line));
                    // Attempt to parse Claude stream-json lines and convert to session logs
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) {
                        // Map type
                        let typ = match v.get("type").and_then(|s| s.as_str()).unwrap_or("") {
                            "user" | "user_message" => control_center::LogType::UserMessage,
                            "assistant" | "assistant_message" => control_center::LogType::AssistantMessage,
                            "tool_call" | "tool_use" => control_center::LogType::ToolCall,
                            "tool_result" | "tool_response" => control_center::LogType::ToolResult,
                            "status" => control_center::LogType::Status,
                            "error" => control_center::LogType::Error,
                            _ => control_center::LogType::Unknown,
                        };
                        // Extract human-friendly message
                        let msg = if let Some(m) = v.get("message").and_then(|s| s.as_str()) {
                            m.to_string()
                        } else if let Some(content) = v.get("content") {
                            if let Some(s) = content.as_str() { s.to_string() } else if let Some(obj) = content.as_object() {
                                obj.get("text").and_then(|x| x.as_str()).unwrap_or("").to_string()
                            } else { serde_json::to_string(content).unwrap_or_default() }
                        } else { String::new() };
                        let log = control_center::ParsedLogLine {
                            timestamp: std::time::SystemTime::now(),
                            entry_type: typ,
                            content: if msg.is_empty() { line.clone() } else { msg },
                            raw: line.clone(),
                        };
                        self.session_logs.push(log);
                        if self.log_scroll.auto_scroll {
                            self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
                        }
                        // Trim to cap
                        const MAX_LOGS: usize = 1000;
                        if self.session_logs.len() > MAX_LOGS {
                            let remove_count = self.session_logs.len() - MAX_LOGS;
                            self.session_logs.drain(0..remove_count);
                            if self.log_scroll.offset >= remove_count { self.log_scroll.offset -= remove_count; } else { self.log_scroll.offset = 0; }
                        }
                    }
                }
                ExecutorOutput::Stderr(line) => {
                    self.append_output(format!("{} {} error: {}", prefixes::WARN, self.center.executor.name(), line));
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
            self.append_output(format!("{} {} session completed", prefixes::EXEC, self.center.executor.name()));
            // Ensure center releases session handle
            self.mode = Mode::Idle;
        }
        
        Ok(())
    }
    
    #[cfg(feature = "tui-input")]
    pub async fn handle_text_input(&mut self) -> Result<()> {
        if !self.input.is_empty() {
            let text = self.input.clone();
            self.append_output(format!("{} {}", prefixes::UTTERANCE, text));
            self.input.clear();
            // Send into headless core as user_text
            if let Some(tx) = &self.core_in_tx {
                let msg = protocol::Message::user_text(text, Some("tui".to_string()), true);
                let _ = tx.send(msg).await;
            }
        }
        Ok(())
    }
    
    #[cfg(not(feature = "tui-input"))]
    pub async fn handle_text_input(&mut self) -> Result<()> { Ok(()) }

    #[cfg(feature = "tui-stt")]
    pub fn update_blink(&mut self) {
        if self.recording.last_blink.elapsed() > Duration::from_millis(constants::BLINK_INTERVAL_MS) {
            self.recording.blink_state = !self.recording.blink_state;
            self.recording.last_blink = std::time::Instant::now();
        }
    }
    
    #[cfg(not(feature = "tui-stt"))]
    pub fn update_blink(&mut self) {}

    #[cfg(feature = "tui-stt")]
    pub fn get_recording_time(&self) -> String {
        let elapsed = self.recording.elapsed_seconds();
        format!("{:02}:{:02}", elapsed / 60, elapsed % 60)
    }

    #[cfg(not(feature = "tui-stt"))]
    pub fn get_recording_time(&self) -> String { "00:00".to_string() }

    /// Helper: whether we are currently in recording mode (feature-gated).
    #[cfg(feature = "tui-stt")]
    pub fn is_recording_mode(&self) -> bool { self.mode == Mode::Recording }
    #[cfg(not(feature = "tui-stt"))]
    pub fn is_recording_mode(&self) -> bool { false }

    pub fn can_edit_input(&self) -> bool {
        #[cfg(feature = "tui-input")]
        {
            return self.mode == Mode::Idle;
        }
        #[cfg(not(feature = "tui-input"))]
        {
            return false;
        }
    }

    #[cfg(feature = "tui-stt")]
    pub fn can_start_recording(&self) -> bool {
        self.mode == Mode::Idle && !self.recording.is_active
    }

    #[cfg(feature = "tui-stt")]
    pub fn can_stop_recording(&self) -> bool {
        self.mode == Mode::Recording && self.recording.is_active
    }

    #[allow(dead_code)]
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
        #[cfg(feature = "tui-stt")]
        {
            return matches!(
                self.mode,
                Mode::Recording | Mode::PlanPending | Mode::ExecutorRunning | Mode::ConfirmingExecutor | Mode::ShowingError
            );
        }
        #[cfg(not(feature = "tui-stt"))]
        {
            return matches!(
                self.mode,
                Mode::PlanPending | Mode::ExecutorRunning | Mode::ConfirmingExecutor | Mode::ShowingError
            );
        }
    }
    
    /// Poll for new log entries
    pub async fn poll_logs(&mut self) -> Result<()> {
        // Pull logs from control center
        for log in self.center.poll_logs(10).await {
            self.session_logs.push(log);
            if self.log_scroll.auto_scroll {
                self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
            }
        }
        // Trim logs if too many
        const MAX_LOGS: usize = 1000;
        if self.session_logs.len() > MAX_LOGS {
            let remove_count = self.session_logs.len() - MAX_LOGS;
            self.session_logs.drain(0..remove_count);
            if self.log_scroll.offset >= remove_count {
                self.log_scroll.offset -= remove_count;
            } else {
                self.log_scroll.offset = 0;
            }
        }
        Ok(())
    }

    /// Attempt to connect to relay if env vars are present
    pub async fn init_relay(&mut self) {
        // Start headless core once at initialization
        let exec_adapter = crate::core_bridge::ExecutorAdapter::new(self.cmd_tx.clone());
        let handles = crate::core_bridge::start_core_with_executor(exec_adapter);
        self.core_in_tx = Some(handles.inbound_tx);
        self.core_out_rx = Some(handles.outbound_rx);
        match relay_client::load_config_from_env() {
            Ok(Some(cfg)) => {
                self.append_output(format!("{} Connecting to relay...", prefixes::RELAY));
                match relay_client::start(cfg).await {
                    Ok(rx) => {
                        self.relay_rx = Some(rx);
                        self.append_output(format!("{} Relay client started", prefixes::RELAY));
                    }
                    Err(e) => {
                        self.append_output(format!("{} Failed to start relay: {}", prefixes::RELAY, e));
                    }
                }
            }
            Ok(None) => {
                // Silent if not configured; user may only use local features.
            }
            Err(e) => {
                self.append_output(format!("{} Relay config error: {}", prefixes::RELAY, e));
            }
        }
    }

    /// Poll relay events non-blocking and display in TUI
    pub async fn poll_relay(&mut self) -> Result<()> {
        if let Some(rx) = &mut self.relay_rx {
            // Drain events first to avoid borrow conflicts
            let mut pending = Vec::with_capacity(50);
            for _ in 0..50 {
                match rx.try_recv() {
                    Ok(ev) => pending.push(ev),
                    Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                    Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                        pending.push(RelayEvent::Status("disconnected".into()));
                        self.relay_rx = None;
                        break;
                    }
                }
            }
            for ev in pending {
                match ev {
                    RelayEvent::Status(s) => self.append_output(format!("{} {}", prefixes::RELAY, s)),
                    RelayEvent::PeerJoined(who) => self.append_output(format!("{} peer joined: {}", prefixes::RELAY, who)),
                    RelayEvent::PeerLeft(who) => self.append_output(format!("{} peer left: {}", prefixes::RELAY, who)),
                    RelayEvent::SessionKilled => self.append_output(format!("{} session killed", prefixes::RELAY)),
                    RelayEvent::Error(e) => self.append_output(format!("{} error: {}", prefixes::RELAY, e)),
                    RelayEvent::Frame(text) => {
                        // Try to parse known frames
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                            if v.get("type").and_then(|s| s.as_str()) == Some("user_text") {
                                let preview = v.get("text").and_then(|s| s.as_str()).unwrap_or("");
                                let preview = if preview.len() > 60 { format!("{}…", &preview[..60]) } else { preview.to_string() };
                                self.append_output(format!("{} user_text: {}", prefixes::RELAY, preview));
                                if let Some(tx) = &self.core_in_tx {
                                    if let Ok(msg) = serde_json::from_value::<protocol::Message>(v.clone()) {
                                        let _ = tx.send(msg).await;
                                    }
                                }
                                continue;
                            }
                            if v.get("type").and_then(|s| s.as_str()) == Some("get_logs") {
                                let reply_id = v.get("id").and_then(|s| s.as_str()).unwrap_or("").to_string();
                                let mut limit = v.get("limit").and_then(|n| n.as_u64()).unwrap_or(100);
                                if limit == 0 { limit = 1; }
                                if limit > 200 { limit = 200; }
                                // Collect latest N logs from memory
                                let mut items: Vec<serde_json::Value> = Vec::new();
                                for log in self.session_logs.iter().rev().take(limit as usize) {
                                    let ts_ms = match log.timestamp.duration_since(std::time::UNIX_EPOCH) {
                                        Ok(d) => d.as_millis() as u64,
                                        Err(_) => 0,
                                    };
                                    let typ = match log.entry_type {
                                        control_center::LogType::UserMessage => "user",
                                        control_center::LogType::AssistantMessage => "assistant",
                                        control_center::LogType::ToolCall => "tool_call",
                                        control_center::LogType::ToolResult => "tool_result",
                                        control_center::LogType::Status => "status",
                                        control_center::LogType::Error => "error",
                                        control_center::LogType::Unknown => "unknown",
                                    };
                                    items.push(serde_json::json!({
                                        "ts": ts_ms,
                                        "type": typ,
                                        "message": log.content,
                                    }));
                                }
                                // If no logs yet, return a few placeholder entries to validate end-to-end flow
                                if items.is_empty() {
                                    let now_ms: u64 = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) { Ok(d) => d.as_millis() as u64, Err(_) => 0 };
                                    let count = std::cmp::min(3usize, limit as usize);
                                    let placeholders = [
                                        "No logs yet — placeholder entry",
                                        "Try launching an executor or sending a command",
                                        "This is a test log to confirm wiring",
                                    ];
                                    for i in 0..count {
                                        let msg = placeholders.get(i).unwrap_or(&"placeholder");
                                        items.push(serde_json::json!({
                                            "ts": now_ms.saturating_sub(((count - i) as u64) * 1000),
                                            "type": "status",
                                            "message": *msg,
                                        }));
                                    }
                                }
                                let resp = serde_json::json!({
                                    "type": "logs",
                                    "replyTo": reply_id,
                                    "items": items,
                                });
                                crate::relay_client::send_frame(resp.to_string());
                                continue;
                            }
                        }
                        // Fallback: echo relay frame
                        self.append_output(format!("{} {}", prefixes::RELAY, text));
                    }
                }
            }
        }
        Ok(())
    }

    /// Poll outbound messages from headless core and reflect in UI state
    pub async fn poll_core_outbound(&mut self) -> Result<()> {
        if let Some(rx) = &mut self.core_out_rx {
            // Drain into a buffer to avoid borrow conflicts
            let mut buffered: Vec<protocol::Message> = Vec::with_capacity(50);
            for _ in 0..50 {
                match rx.try_recv() {
                    Ok(msg) => buffered.push(msg),
                    Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                    Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => { self.core_out_rx = None; break; }
                }
            }
            for msg in buffered {
                match msg {
                    protocol::Message::Status(s) => {
                        self.append_output(format!("{} {}", prefixes::PLAN, s.text));
                    }
                    protocol::Message::PromptConfirmation(pc) => {
                        self.pending_executor = Some(PendingExecutor {
                            prompt: pc.prompt,
                            executor_name: self.center.executor.name().to_string(),
                            working_dir: ExecutorConfig::default().working_dir.to_string_lossy().to_string(),
                        });
                        self.mode = Mode::ConfirmingExecutor;
                        self.append_output(format!("{} Ready to launch {}. Press Enter to confirm, Escape to cancel.", prefixes::PLAN, self.center.executor.name()));
                    }
                    _ => {}
                }
            }
        }
        Ok(())
    }

    /// Poll commands destined to the App (from core executor adapter)
    pub async fn poll_app_commands(&mut self) -> Result<()> {
        let mut buffered: Vec<crate::core_bridge::AppCommand> = Vec::with_capacity(20);
        for _ in 0..20 {
            match self.cmd_rx.try_recv() {
                Ok(cmd) => buffered.push(cmd),
                Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => break,
            }
        }
        for cmd in buffered {
            match cmd {
                crate::core_bridge::AppCommand::LaunchExecutor { prompt } => {
                    let _ = self.launch_executor(&prompt).await;
                }
            }
        }
        Ok(())
    }
}
