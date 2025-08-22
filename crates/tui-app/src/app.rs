use anyhow::Result;
use std::time::Duration;

use crate::backend;
use crate::constants::{self, messages, prefixes};
use crate::executor::{ExecutorSession, ExecutorFactory, ExecutorType, ExecutorConfig, ExecutorOutput};
use crate::settings::AppSettings;
use crate::types::{Mode, PlanState, RecordingState, PendingExecutor};
use llm_interface::RouterAction;

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
        }
    }
    
    /// Clean up any running executor sessions before exit
    pub async fn cleanup(&mut self) {
        if let Some(mut session) = self.executor_session.take() {
            let _ = session.terminate().await;
        }
    }

    pub fn append_output(&mut self, line: String) {
        self.output.push(line);
        self.trim_output();
    }

    fn trim_output(&mut self) {
        if self.output.len() > constants::MAX_OUTPUT_LINES {
            self.output.remove(0);
        }
    }

    pub async fn start_recording(&mut self) -> Result<()> {
        self.mode = Mode::Recording;
        self.recording.start();
        backend::record_voice(true).await?;
        self.append_output(format!("{} Recording started...", prefixes::ASR));
        Ok(())
    }

    pub async fn stop_recording(&mut self) -> Result<()> {
        backend::record_voice(false).await?;
        let audio = backend::take_recorded_audio().await?;
        
        if audio.is_empty() {
            self.handle_empty_recording();
        } else {
            self.append_output(format!("{} Processing audio...", prefixes::ASR));
            self.process_audio(audio).await?;
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
            _ => {}
        }
    }

    async fn route_command(&mut self, text: &str) -> Result<()> {
        self.append_output(format!("{} Routing command...", prefixes::PLAN));
        
        // Get router response from LLM
        let response_json = backend::text_to_llm_cmd(text).await?;
        let response = backend::parse_router_response(&response_json).await?;
        
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
                    self.append_output(format!("{}: {}", self.current_executor.name(), line));
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
        matches!(self.mode, Mode::Recording | Mode::PlanPending | Mode::ExecutorRunning | Mode::ConfirmingExecutor)
    }
}