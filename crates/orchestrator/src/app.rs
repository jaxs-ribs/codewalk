use anyhow::Result;
#[cfg(feature = "tui-stt")]
use std::time::Duration;
use std::collections::HashMap;
use std::path::PathBuf;
use std::fs;
use std::io::Write;

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
// For base64 decode on get_logs/stt frames
use base64::Engine as _;
 

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
    // Session management
    pub current_session_id: Option<String>,
    pub session_logs_map: HashMap<String, Vec<ParsedLogLine>>,
    pub artifacts_dir: PathBuf,
    // Active executor session tracking
    pub active_executor_session_id: Option<String>,
    pub active_executor_type: Option<control_center::ExecutorType>,
    pub active_executor_started_at: Option<std::time::Instant>,
    // Core reference for session notifications
    pub core: Option<std::sync::Arc<orchestrator_core::OrchestratorCore<crate::core_bridge::RouterAdapter, crate::core_bridge::ExecutorAdapter, crate::core_bridge::OutboundChannel>>>,
    // Log summarizer for session status queries
    pub log_summarizer: crate::log_summarizer::LogSummarizer,
    // Session history
    pub last_session_summary: Option<String>,
    pub last_session_time: Option<std::time::Instant>,
    pub last_completed_session_id: Option<String>,  // For resumption
    // Summary caching
    pub cached_summary: Option<String>,
    pub cached_summary_time: Option<std::time::Instant>,
}

impl App {
    pub fn new() -> Self {
        let settings = AppSettings::load();
        let (cmd_tx, cmd_rx) = tokio::sync::mpsc::channel(100);
        
        // Create artifacts directory
        let artifacts_dir = PathBuf::from("artifacts");
        if !artifacts_dir.exists() {
            let _ = fs::create_dir_all(&artifacts_dir);
        }
        
        // Generate initial session ID for startup logs
        let initial_session_id = Self::generate_session_id_static();
        let mut session_logs_map = HashMap::new();
        session_logs_map.insert(initial_session_id.clone(), Vec::new());
        
        let mut log_summarizer = crate::log_summarizer::LogSummarizer::new();
        let _ = log_summarizer.initialize(); // Initialize Groq client
        
        let mut app = Self {
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
            current_session_id: Some(initial_session_id),
            session_logs_map,
            artifacts_dir,
            active_executor_session_id: None,
            active_executor_type: None,
            active_executor_started_at: None,
            core: None,
            log_summarizer,
            last_session_summary: None,
            last_session_time: None,
            last_completed_session_id: None,
            cached_summary: None,
            cached_summary_time: None,
        };
        
        // Load previous session info from disk
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(app.load_previous_session())
        });
        
        app
    }
    
    /// Clean up any running executor sessions before exit
    pub async fn cleanup(&mut self) {
        // Save current session logs before exit
        if let Some(session_id) = &self.current_session_id {
            self.save_session_logs_to_disk(session_id);
        }
        let _ = self.center.terminate().await;
    }

    pub(crate) fn append_output(&mut self, line: String) {
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
                // Save logs before terminating
                if let Some(session_id) = &self.current_session_id {
                    self.save_session_logs_to_disk(session_id);
                }
                // Try to terminate executor gracefully
                let _ = tokio::task::block_in_place(|| {
                    tokio::runtime::Handle::current().block_on(self.center.terminate())
                });
                
                // Notify core that the session has ended
                if let Some(core) = &self.core {
                    core.clear_active_session();
                }
                
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
        // If we're in confirmation mode, handle the response differently
        if self.mode == Mode::ConfirmingExecutor {
            return self.handle_confirmation_response(text).await;
        }
        
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
                            confirmation_id: None,  // This path doesn't use core, so no ID
                            is_initial_prompt: true,
                            session_action: None,
                        });
                        self.mode = Mode::ConfirmingExecutor;
                        
                        // Show better message based on whether we have a previous session
                        let confirmation_msg = if self.last_completed_session_id.is_some() {
                            if let Some(summary) = &self.last_session_summary {
                                format!("{} Should I start Claude for: {}?\n   Previous: {}\n   Say 'continue', 'new', or 'no'", 
                                    prefixes::PLAN, prompt, summary)
                            } else {
                                format!("{} Should I start Claude for: {}?\n   Say 'continue previous', 'start new', or 'no'", 
                                    prefixes::PLAN, prompt)
                            }
                        } else {
                            format!("{} Should I start Claude for: {}?\n   Say 'yes' or 'no'", 
                                prefixes::PLAN, prompt)
                        };
                        self.append_output(confirmation_msg);
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
            // These should only appear in confirmation context, not normal routing
            RouterAction::ContinuePrevious | RouterAction::StartNew | 
            RouterAction::DeclineSession | RouterAction::AmbiguousConfirmation | 
            RouterAction::UnintelligibleResponse => {
                self.append_output(format!("{} Unexpected confirmation response in normal routing context", prefixes::PLAN));
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    pub(crate) async fn launch_executor_with_resume(&mut self, prompt: &str, resume_session_id: &str) -> Result<()> {
        // Don't generate new ID, we're resuming
        self.start_new_session(resume_session_id.to_string());
        
        self.append_output(format!("{} Resuming {} session {}...", prefixes::EXEC, self.center.executor.name(), &resume_session_id[..8.min(resume_session_id.len())]));

        // Create a config with default settings
        let config = ExecutorConfig::default();
        
        match self.center.launch_with_resume(prompt, resume_session_id, Some(config.clone())).await {
            Ok(()) => {
                self.mode = Mode::ExecutorRunning;
                
                // Store active executor session information
                self.active_executor_type = Some(self.center.executor.clone());
                self.active_executor_started_at = Some(std::time::Instant::now());
                self.active_executor_session_id = Some(resume_session_id.to_string());
                
                // Notify core that a session has resumed
                if let Some(core) = &self.core {
                    core.set_active_session(self.center.executor.name().to_string());
                }
                
                self.append_output(format!("{} Resumed {} session", prefixes::EXEC, self.center.executor.name()));
                self.append_output(format!("Working directory: {:?}", config.working_dir));
                self.append_output(format!("Continuing with: {}", prompt));
                
                // Save resumed session info to disk
                self.save_session_status(resume_session_id, "Resumed session", "active");
                Ok(())
            }
            Err(e) => {
                self.show_error_with_details(
                    "Failed to resume executor",
                    &format!("Could not resume {} session", self.center.executor.name()),
                    format!("Error: {}\n\nYou may want to start a fresh session instead.", e)
                );
                self.mode = Mode::Idle;
                Err(e)
            }
        }
    }
    
    pub(crate) async fn launch_executor(&mut self, prompt: &str) -> Result<()> {
        // Generate new session ID
        let session_id = self.generate_session_id();
        self.start_new_session(session_id.clone());
        
        self.append_output(format!("{} Starting {} (session: {})...", prefixes::EXEC, self.center.executor.name(), &session_id[..8]));

        let config = ExecutorConfig::default();
        match self.center.launch(prompt, Some(config.clone())).await {
            Ok(()) => {
                self.mode = Mode::ExecutorRunning;
                
                // Store active executor session information
                self.active_executor_type = Some(self.center.executor.clone());
                self.active_executor_started_at = Some(std::time::Instant::now());
                
                // Session ID will be captured from executor output
                self.active_executor_session_id = None;
                
                // Notify core that a session has started
                if let Some(core) = &self.core {
                    core.set_active_session(self.center.executor.name().to_string());
                }
                
                self.append_output(format!("{} {} session started", prefixes::EXEC, self.center.executor.name()));
                self.append_output(format!("Working directory: {:?}", config.working_dir));
                self.append_output(format!("Prompt: {}", prompt));
                
                // Save initial session info to disk
                self.save_session_metadata(&session_id, prompt, &config.working_dir);
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
                        // Capture session_id if we haven't yet
                        if self.active_executor_session_id.is_none() {
                            if let Some(sid) = v.get("session_id").and_then(|s| s.as_str()) {
                                self.active_executor_session_id = Some(sid.to_string());
                                self.active_executor_started_at = Some(std::time::Instant::now());
                                self.active_executor_type = Some(control_center::ExecutorType::Claude);
                                self.append_output(format!("{} Captured Claude session ID: {}", prefixes::EXEC, sid));
                                
                                // Save initial session status
                                self.save_session_status(sid, "Session started", "active");
                            }
                        }
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
                        self.add_log_to_current_session(log);
                        if self.log_scroll.auto_scroll {
                            self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
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
            
            // Log the session ID that was captured
            if let Some(sid) = &self.active_executor_session_id {
                self.append_output(format!("{} Claude session ID was: {}", prefixes::EXEC, sid));
            }
            
            // Generate and save last session summary before clearing
            if !self.session_logs.is_empty() || (self.current_session_id.is_some() && 
                self.session_logs_map.get(self.current_session_id.as_ref().unwrap())
                    .map(|logs| !logs.is_empty()).unwrap_or(false)) {
                // Generate summary for the ending session
                match self.log_summarizer.summarize_logs(
                    if let Some(session_id) = &self.current_session_id {
                        self.session_logs_map.get(session_id).map(|v| v.as_slice()).unwrap_or(&[])
                    } else {
                        &self.session_logs
                    }
                ).await {
                    Ok(summary) => {
                        // Save session completion details
                        if let Some(session_id) = &self.active_executor_session_id {
                            self.save_session_status(session_id, &summary, "completed");
                            crate::logger::log_event("SESSION", &format!("Session {} completed with summary: {}", session_id, summary));
                            // Store the session ID for potential resumption
                            self.last_completed_session_id = Some(session_id.clone());
                        }
                        
                        self.last_session_summary = Some(summary);
                        self.last_session_time = Some(std::time::Instant::now());
                        crate::logger::log_event("SESSION", "Saved last session summary");
                    },
                    Err(e) => {
                        crate::logger::log_error("SESSION", &format!("Failed to save last session summary: {}", e));
                    }
                }
            }
            
            // Clear cache since session is ending
            self.cached_summary = None;
            self.cached_summary_time = None;
            
            // Notify core that the session has ended
            if let Some(core) = &self.core {
                core.clear_active_session();
            }
            
            // Clear active executor session info
            self.active_executor_session_id = None;
            self.active_executor_type = None;
            self.active_executor_started_at = None;
            
            // Save session logs to disk when session ends
            if let Some(session_id) = &self.current_session_id {
                self.save_session_logs_to_disk(session_id);
                self.append_output(format!("{} Session logs saved to artifacts/{}", prefixes::EXEC, session_id));
            }
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
            
            // If we're in ConfirmingExecutor mode, handle as confirmation response
            if self.mode == Mode::ConfirmingExecutor {
                crate::logger::log_event("CONFIRMATION", &format!("Handling TUI input '{}' as confirmation response", text));
                return self.handle_confirmation_response(&text).await;
            }
            
            // Otherwise, send into headless core as user_text for normal routing
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
            self.add_log_to_current_session(log);
            if self.log_scroll.auto_scroll {
                self.log_scroll.scroll_to_bottom(self.session_logs.len().saturating_sub(1));
            }
        }
        Ok(())
    }

    /// Attempt to connect to relay if env vars are present
    pub async fn init_relay(&mut self) {
        // Start headless core once at initialization
        let exec_adapter = crate::core_bridge::ExecutorAdapter::new(self.cmd_tx.clone());
        let system = crate::core_bridge::start_core_with_executor(exec_adapter);
        self.core_in_tx = Some(system.handles.inbound_tx.clone());
        self.core_out_rx = Some(system.handles.outbound_rx);
        self.core = Some(system.core);
        crate::logger::log_event("INIT", "Core initialized and channels connected");
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
                            let msg_type = v.get("type").and_then(|s| s.as_str());
                            
                            if msg_type == Some("user_text") {
                                let text = v.get("text").and_then(|s| s.as_str()).unwrap_or("");
                                let preview = if text.len() > 60 { format!("{}…", &text[..60]) } else { text.to_string() };
                                self.append_output(format!("{} user_text: {}", prefixes::RELAY, preview));
                                
                                // If we're in ConfirmingExecutor mode, handle as confirmation response
                                if self.mode == Mode::ConfirmingExecutor {
                                    crate::logger::log_event("CONFIRMATION", &format!("Handling user_text '{}' as confirmation response", text));
                                    if let Err(e) = self.handle_confirmation_response(text).await {
                                        self.append_output(format!("{} Error handling confirmation: {}", prefixes::EXEC, e));
                                    }
                                } else {
                                    crate::logger::log_event("ROUTING", &format!("Mode is {:?}, routing user_text '{}' normally", self.mode, text));
                                    // Otherwise, send to core for normal routing
                                    if let Some(tx) = &self.core_in_tx {
                                        if let Ok(msg) = serde_json::from_value::<protocol::Message>(v.clone()) {
                                            let _ = tx.send(msg).await;
                                        }
                                    }
                                }
                                continue;
                            }
                            
                            if msg_type == Some("confirm_response") {
                                // Handle confirmation response from mobile
                                self.append_output(format!("{} Mobile confirmation received", prefixes::RELAY));
                                if let Some(tx) = &self.core_in_tx {
                                    if let Ok(msg) = serde_json::from_value::<protocol::Message>(v.clone()) {
                                        let _ = tx.send(msg).await;
                                        // Dismiss the TUI confirmation dialog if mobile confirmed
                                        if self.mode == Mode::ConfirmingExecutor {
                                            self.pending_executor = None;
                                            self.mode = Mode::Idle;
                                        }
                                    }
                                }
                                continue;
                            }
                            if v.get("type").and_then(|s| s.as_str()) == Some("get_logs") {
                                let reply_id = v.get("id").and_then(|s| s.as_str()).unwrap_or("").to_string();
                                let mut limit = v.get("limit").and_then(|n| n.as_u64()).unwrap_or(100);
                                if limit == 0 { limit = 1; }
                                if limit > 200 { limit = 200; }
                                // Collect latest N logs from current session
                                let mut items: Vec<serde_json::Value> = Vec::new();
                                
                                // Get logs from current session or fall back to display logs
                                let logs_to_use = if let Some(session_id) = &self.current_session_id {
                                    self.session_logs_map.get(session_id).unwrap_or(&self.session_logs)
                                } else {
                                    &self.session_logs
                                };
                                
                                for log in logs_to_use.iter().rev().take(limit as usize) {
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
                                    "session_id": self.current_session_id.clone().unwrap_or_else(|| "none".to_string()),
                                    "items": items,
                                });
                                crate::relay_client::send_frame(resp.to_string());
                                continue;
                            }
                            if v.get("type").and_then(|s| s.as_str()) == Some("get_filtered_logs") {
                                // New endpoint for getting filtered logs suitable for summarization
                                let reply_id = v.get("id").and_then(|s| s.as_str()).unwrap_or("").to_string();
                                let mut limit = v.get("limit").and_then(|n| n.as_u64()).unwrap_or(100);
                                if limit == 0 { limit = 1; }
                                if limit > 200 { limit = 200; }
                                
                                // Get logs from current session
                                let logs_to_use = if let Some(session_id) = &self.current_session_id {
                                    self.session_logs_map.get(session_id).unwrap_or(&self.session_logs)
                                } else {
                                    &self.session_logs
                                };
                                
                                // Apply executor-specific filtering
                                let filtered_logs: Vec<String> = if !logs_to_use.is_empty() {
                                    // Take the last N logs and filter them
                                    let recent_logs: Vec<_> = logs_to_use.iter()
                                        .rev()
                                        .take(limit as usize)
                                        .rev()
                                        .cloned()
                                        .collect();
                                    self.center.executor.filter_logs_for_summary(&recent_logs)
                                } else {
                                    vec!["No activity yet".to_string()]
                                };
                                
                                let resp = serde_json::json!({
                                    "type": "filtered_logs",
                                    "replyTo": reply_id,
                                    "session_id": self.current_session_id.clone().unwrap_or_else(|| "none".to_string()),
                                    "executor": self.center.executor.name(),
                                    "items": filtered_logs,
                                });
                                crate::relay_client::send_frame(resp.to_string());
                                continue;
                            }
                            if v.get("type").and_then(|s| s.as_str()) == Some("stt_audio") {
                                let reply_id = v.get("id").and_then(|s| s.as_str()).unwrap_or("").to_string();
                                let mime = v.get("mime").and_then(|s| s.as_str()).unwrap_or("");
                                let b64 = v.get("b64").and_then(|b| b.as_bool()).unwrap_or(true);
                                let mut text_out = String::new();
                                if let Some(data) = v.get("data").and_then(|s| s.as_str()) {
                                    let audio_bytes = if b64 { base64::engine::general_purpose::STANDARD.decode(data).unwrap_or_default() } else { Vec::new() };
                                    #[cfg(feature = "tui-stt")]
                                    {
                                        if !audio_bytes.is_empty() {
                                            match crate::backend::voice_to_text(audio_bytes).await {
                                                Ok(t) => {
                                                    text_out = t;
                                                    // Route the recognized text as a command, similar to TUI mic flow
                                                    let _ = self.route_command(&text_out).await;
                                                }
                                                Err(e) => {
                                                    self.append_output(format!("{} STT error: {}", prefixes::ASR, e));
                                                }
                                            }
                                        }
                                    }
                                }
                                let resp = serde_json::json!({
                                    "type": "stt_result",
                                    "replyTo": reply_id,
                                    "mime": mime,
                                    "ok": !text_out.is_empty(),
                                    "text": text_out,
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
                    Ok(msg) => {
                        crate::logger::log_event("CORE_OUT_POLL", &format!("Got message: {:?}", msg));
                        buffered.push(msg);
                    }
                    Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                    Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => { 
                        crate::logger::log_event("CORE_OUT_POLL", "Channel disconnected!");
                        self.core_out_rx = None; 
                        break; 
                    }
                }
            }
            if !buffered.is_empty() {
                crate::logger::log_event("CORE_OUT", &format!("Processing {} messages from core", buffered.len()));
            }
            for msg in buffered {
                match msg {
                    protocol::Message::Status(ref s) => {
                        self.append_output(format!("{} {}", prefixes::PLAN, s.text));
                        // Forward status message to mobile via relay
                        let status_json = serde_json::to_string(&msg).unwrap_or_default();
                        self.append_output(format!("DEBUG: Sending Status to relay: {}", status_json));
                        relay_client::send_frame(status_json);
                    }
                    protocol::Message::PromptConfirmation(ref pc) => {
                        crate::logger::log_event("CORE_OUT", &format!("Received PromptConfirmation for: {}", pc.prompt));
                        // Forward confirmation request to mobile via relay
                        let confirmation_json = serde_json::to_string(&msg).unwrap_or_default();
                        relay_client::send_frame(confirmation_json);
                        
                        self.pending_executor = Some(PendingExecutor {
                            prompt: pc.prompt.clone(),
                            executor_name: self.center.executor.name().to_string(),
                            working_dir: ExecutorConfig::default().working_dir.to_string_lossy().to_string(),
                            confirmation_id: pc.id.clone(),
                            is_initial_prompt: true,
                            session_action: None,
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
                crate::core_bridge::AppCommand::QueryExecutorStatus { reply_tx } => {
                    let summary = self.get_session_summary().await;
                    let _ = reply_tx.send(summary);
                }
            }
        }
        Ok(())
    }
    
    /// Get a summary of the current session's activity
    pub async fn get_session_summary(&mut self) -> String {
        crate::logger::log_event("SUMMARY", "get_session_summary called");
        
        // Check if there's an active executor session
        if self.active_executor_session_id.is_none() {
            crate::logger::log_event("SUMMARY", "No active session");
            
            // First check in-memory last session
            if let Some(ref last_summary) = self.last_session_summary {
                if let Some(last_time) = self.last_session_time {
                    let elapsed = last_time.elapsed();
                    if elapsed.as_secs() < 60 { // Within 1 minute - just completed
                        return format!("I just finished {}", last_summary);
                    } else if elapsed.as_secs() < 300 { // Within 5 minutes
                        return format!("A few minutes ago, I {}", last_summary);
                    } else if elapsed.as_secs() < 3600 { // Within an hour
                        return format!("Earlier, I {}", last_summary);
                    }
                }
                return format!("Previously, I {}", last_summary);
            }
            
            // Try to load from disk if not in memory
            if let Some((_, summary)) = self.load_previous_session().await {
                return format!("In our last session, I {}", summary);
            }
            
            return "I'm not working on anything right now.".to_string();
        }
        
        // Check cache (valid for 10 seconds)
        if let Some(ref cached) = self.cached_summary {
            if let Some(cached_time) = self.cached_summary_time {
                if cached_time.elapsed().as_secs() < 10 {
                    crate::logger::log_event("SUMMARY", "Returning cached summary");
                    return cached.clone();
                }
            }
        }
        
        // Get session logs
        let logs = if let Some(session_id) = &self.current_session_id {
            if let Some(session_logs) = self.session_logs_map.get(session_id) {
                session_logs.clone()
            } else {
                Vec::new()
            }
        } else {
            self.session_logs.clone()
        };
        
        crate::logger::log_event("SUMMARY", &format!("Found {} logs to summarize", logs.len()));
        
        // If no logs yet, return generic message
        if logs.is_empty() {
            let msg = "Claude is starting to work on your request".to_string();
            self.cached_summary = Some(msg.clone());
            self.cached_summary_time = Some(std::time::Instant::now());
            return msg;
        }
        
        // Get summary from log summarizer  
        match self.log_summarizer.summarize_logs(&logs).await {
            Ok(summary) => {
                // Just return the conversational summary without technical details
                let session_info = format!("I'm {}", summary);
                
                crate::logger::log_event("SUMMARY", &format!("Generated summary: {}", session_info));
                // Cache the summary
                self.cached_summary = Some(session_info.clone());
                self.cached_summary_time = Some(std::time::Instant::now());
                session_info
            },
            Err(e) => {
                crate::logger::log_error("SUMMARY", &format!("Failed to summarize: {}", e));
                // Fallback to basic conversational message
                let msg = "I'm working on your request right now.".to_string();
                self.cached_summary = Some(msg.clone());
                self.cached_summary_time = Some(std::time::Instant::now());
                msg
            }
        }
    }
    
    // Session management methods
    fn generate_session_id_static() -> String {
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
    
    fn generate_session_id(&self) -> String {
        Self::generate_session_id_static()
    }
    
    fn start_new_session(&mut self, session_id: String) {
        // Save previous session logs to disk if exists
        if let Some(prev_id) = &self.current_session_id {
            self.save_session_logs_to_disk(prev_id);
        }
        
        // Set new current session
        self.current_session_id = Some(session_id.clone());
        self.session_logs_map.insert(session_id, Vec::new());
        
        // Clear the current view logs (backward compatibility)
        self.session_logs.clear();
    }
    
    fn save_session_metadata(&self, session_id: &str, prompt: &str, working_dir: &std::path::Path) {
        let session_dir = self.artifacts_dir.join(session_id);
        if let Err(e) = fs::create_dir_all(&session_dir) {
            eprintln!("Failed to create session directory: {}", e);
            return;
        }
        
        let metadata = serde_json::json!({
            "session_id": session_id,
            "prompt": prompt,
            "working_dir": working_dir.to_string_lossy(),
            "started_at": chrono::Utc::now().to_rfc3339(),
            "executor": self.center.executor.name(),
        });
        
        let metadata_path = session_dir.join("metadata.json");
        if let Ok(mut file) = fs::File::create(metadata_path) {
            let _ = file.write_all(serde_json::to_string_pretty(&metadata).unwrap().as_bytes());
        }
    }
    
    pub fn save_session_logs_to_disk(&self, session_id: &str) {
        if let Some(logs) = self.session_logs_map.get(session_id) {
            let session_dir = self.artifacts_dir.join(session_id);
            if let Err(e) = fs::create_dir_all(&session_dir) {
                eprintln!("Failed to create session directory: {}", e);
                return;
            }
            
            // Save logs as JSON for easy parsing
            let logs_json: Vec<serde_json::Value> = logs.iter().map(|log| {
                let ts_ms = log.timestamp.duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default().as_millis() as u64;
                serde_json::json!({
                    "timestamp": ts_ms,
                    "type": format!("{:?}", log.entry_type),
                    "content": log.content,
                    "raw": log.raw,
                })
            }).collect();
            
            let logs_path = session_dir.join("logs.json");
            if let Ok(mut file) = fs::File::create(&logs_path) {
                let _ = file.write_all(serde_json::to_string_pretty(&logs_json).unwrap().as_bytes());
            }
            
            // Also save a human-readable log file
            let readable_path = session_dir.join("logs.txt");
            if let Ok(mut file) = fs::File::create(&readable_path) {
                for log in logs {
                    let timestamp = chrono::DateTime::<chrono::Utc>::from(log.timestamp);
                    let _ = writeln!(file, "[{}] {:?}: {}", 
                        timestamp.format("%H:%M:%S%.3f"),
                        log.entry_type,
                        log.content
                    );
                }
            }
        }
    }
    
    pub fn add_log_to_current_session(&mut self, log: ParsedLogLine) {
        // Add to current session logs
        if let Some(session_id) = &self.current_session_id {
            if let Some(session_logs) = self.session_logs_map.get_mut(session_id) {
                session_logs.push(log.clone());
                
                // Save to disk every 10 logs or immediately for important logs
                let should_save = session_logs.len() % 10 == 0 || 
                    matches!(log.entry_type, 
                        control_center::LogType::Error | 
                        control_center::LogType::UserMessage |
                        control_center::LogType::AssistantMessage
                    );
                
                if should_save {
                    self.save_session_logs_to_disk(session_id);
                }
            }
        }
        
        // Also add to the display logs (backward compatibility)
        self.session_logs.push(log);
        
        // Trim display logs if too many
        const MAX_LOGS: usize = 1000;
        if self.session_logs.len() > MAX_LOGS {
            let remove_count = self.session_logs.len() - MAX_LOGS;
            self.session_logs.drain(0..remove_count);
        }
    }
    
    pub fn save_session_status(&self, session_id: &str, summary: &str, status: &str) {
        let session_dir = self.artifacts_dir.join(format!("session_{}", session_id));
        if !session_dir.exists() {
            let _ = fs::create_dir_all(&session_dir);
        }
        
        // Check if this is a resumed session
        let is_resumed = self.last_completed_session_id.as_ref()
            .map(|id| id == session_id)
            .unwrap_or(false);
        
        let metadata = serde_json::json!({
            "session_id": session_id,
            "status": status,
            "summary": summary,
            "completed_at": chrono::Utc::now().to_rfc3339(),
            "executor_type": self.active_executor_type.as_ref().map(|t| format!("{:?}", t)),
            "duration_secs": self.active_executor_started_at.map(|t| t.elapsed().as_secs()),
            "is_resumed": is_resumed,
            "resumed_from": if is_resumed { self.last_completed_session_id.clone() } else { None },
        });
        
        let metadata_path = session_dir.join("metadata.json");
        if let Ok(mut file) = fs::File::create(&metadata_path) {
            let _ = file.write_all(serde_json::to_string_pretty(&metadata).unwrap().as_bytes());
        }
    }
    
    pub async fn load_previous_session(&mut self) -> Option<(String, String)> {
        // Look for the most recent session in artifacts directory
        let mut sessions = Vec::new();
        
        if let Ok(entries) = fs::read_dir(&self.artifacts_dir) {
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if path.is_dir() {
                        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                            if name.starts_with("session_") {
                                let metadata_path = path.join("metadata.json");
                                if metadata_path.exists() {
                                    if let Ok(content) = fs::read_to_string(&metadata_path) {
                                        if let Ok(meta) = serde_json::from_str::<serde_json::Value>(&content) {
                                            sessions.push((
                                                meta["completed_at"].as_str().unwrap_or("").to_string(),
                                                meta["summary"].as_str().unwrap_or("").to_string(),
                                                meta["session_id"].as_str().unwrap_or("").to_string(),
                                            ));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Sort by completion time and return the most recent
        sessions.sort_by(|a, b| b.0.cmp(&a.0));
        
        // Also update last_completed_session_id if we found one
        if let Some((_, _, id)) = sessions.first() {
            self.last_completed_session_id = Some(id.clone());
        }
        
        sessions.first().map(|(_, summary, id)| (id.clone(), summary.clone()))
    }
}
