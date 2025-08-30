use anyhow::Result;
use std::time::Duration;

use crate::backend;
use crate::constants::{self, messages, prefixes};
use crate::relay_client::{self, RelayEvent};
use control_center::{ExecutorConfig, ExecutorOutput};
use control_center::center::ControlCenter;
use crate::settings::AppSettings;
use crate::types::{Mode, PlanState, RecordingState, PendingExecutor, ErrorInfo, ScrollState, ScrollDirection};
use crate::utils::TextWrapper;
use control_center::ParsedLogLine;
use router::RouterAction;
 

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    pub recording: RecordingState,
    pub center: ControlCenter,
    pub settings: AppSettings,
    pub pending_executor: Option<PendingExecutor>,
    pub error_info: Option<ErrorInfo>,
    pub scroll: ScrollState,
    pub session_logs: Vec<ParsedLogLine>,
    pub log_scroll: ScrollState,
    pub relay_rx: Option<tokio::sync::mpsc::Receiver<RelayEvent>>,
    // No direct receiver; logs are pulled via ControlCenter
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
            center: ControlCenter::new(),
            settings,
            pending_executor: None,
            error_info: None,
            scroll: ScrollState::new(),
            session_logs: Vec::new(),
            log_scroll: ScrollState::new(),
            relay_rx: None,
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
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                            let msg = v.get("text").and_then(|s| s.as_str()).unwrap_or_else(|| text.as_str());
                            self.append_output(format!("{} {}", prefixes::RELAY, msg));
                        } else {
                            self.append_output(format!("{} {}", prefixes::RELAY, text));
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
