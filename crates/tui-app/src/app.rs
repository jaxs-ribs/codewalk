use anyhow::Result;
use std::time::Duration;

use crate::backend;
use crate::claude_launcher::{self, ClaudeSession};
use crate::constants::{self, messages, prefixes};
use crate::types::{Mode, PlanState, RecordingState};
use llm_interface::RouterAction;

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    pub recording: RecordingState,
    pub claude_session: Option<ClaudeSession>,
}

impl App {
    pub fn new() -> Self {
        Self {
            output: Vec::new(),
            input: String::new(),
            mode: Mode::Idle,
            plan: PlanState::new(),
            recording: RecordingState::new(),
            claude_session: None,
        }
    }
    
    /// Clean up any running Claude sessions before exit
    pub async fn cleanup(&mut self) {
        if let Some(mut session) = self.claude_session.take() {
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
        } else {
            self.append_output(format!("{} No speech detected", prefixes::ASR));
            self.mode = Mode::Idle;
        }
        Ok(())
    }

    pub async fn create_plan(&mut self, text: &str) -> Result<()> {
        let plan_json = backend::text_to_llm_cmd(text).await?;
        let plan_info = backend::extract_command_plan(&plan_json).await.ok();
        
        if let Some(info) = plan_info {
            self.handle_plan_response(info, plan_json).await?;
        } else {
            self.handle_invalid_plan();
        }
        
        Ok(())
    }

    async fn handle_plan_response(&mut self, info: llm_interface::CommandPlan, json: String) -> Result<()> {
        use llm_interface::PlanStatus;
        
        match info.status {
            PlanStatus::Ok if info.is_valid() => {
                let cmd = backend::extract_cmd(&json).await?;
                self.plan.set(json.clone(), cmd);
                self.mode = Mode::PlanPending;
                self.append_output(format!("{} {}", prefixes::PLAN, json));
            }
            PlanStatus::Deny => {
                let reason = info.reason.unwrap_or_else(|| "unknown".to_string());
                self.append_output(format!("{} {}{}", prefixes::PLAN, messages::PLAN_DENY_PREFIX, reason));
                self.mode = Mode::Idle;
            }
            _ => self.handle_invalid_plan(),
        }
        Ok(())
    }

    fn handle_invalid_plan(&mut self) {
        self.append_output(format!("{} {}", prefixes::PLAN, messages::PLAN_INVALID));
        self.mode = Mode::Idle;
    }

    pub fn execute_plan(&mut self) {
        if let Some(cmd) = &self.plan.command.clone() {
            self.mode = Mode::Executing;
            self.append_output(format!("{} {}", prefixes::EXEC, cmd));
            self.simulate_execution();
            self.complete_execution();
        }
    }

    fn simulate_execution(&mut self) {
        self.append_output(messages::SIMULATED_OUTPUT.to_string());
        self.append_output(messages::DONE.to_string());
    }

    fn complete_execution(&mut self) {
        self.plan.clear();
        self.mode = Mode::Idle;
    }

    pub fn cancel_current_operation(&mut self) {
        match self.mode {
            Mode::PlanPending => {
                self.append_output(format!("{} {}", prefixes::PLAN, messages::PLAN_CANCELED));
                self.plan.clear();
                self.mode = Mode::Idle;
            }
            Mode::Recording => {
                self.recording.stop();
                self.mode = Mode::Idle;
            }
            Mode::ClaudeRunning => {
                if let Some(mut session) = self.claude_session.take() {
                    // Try to terminate Claude gracefully
                    let _ = tokio::task::block_in_place(|| {
                        tokio::runtime::Handle::current().block_on(session.terminate())
                    });
                    self.append_output(format!("{} Claude session terminated by user", prefixes::EXEC));
                }
                self.mode = Mode::Idle;
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
                    self.append_output(format!("{} Launching Claude with: {}", prefixes::EXEC, prompt));
                    self.launch_claude(&prompt).await?;
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
    
    async fn launch_claude(&mut self, prompt: &str) -> Result<()> {
        self.append_output(format!("{} Starting Claude Code...", prefixes::EXEC));
        
        match claude_launcher::launch_claude_session(prompt).await {
            Ok(session) => {
                self.claude_session = Some(session);
                self.mode = Mode::ClaudeRunning;
                self.append_output(format!("{} Claude session started in {}", prefixes::EXEC, claude_launcher::PROJECT_DIR));
                self.append_output(format!("Claude prompt: {}", prompt));
                // Don't block here - output will be polled in main loop
            }
            Err(e) => {
                if e.to_string().contains("No such file or directory") {
                    self.append_output(format!("{} Claude Code not found. Install with: npm install -g @anthropic-ai/claude-code", prefixes::PLAN));
                } else {
                    self.append_output(format!("{} Failed to launch Claude: {}", prefixes::PLAN, e));
                }
                self.mode = Mode::Idle;
            }
        }
        
        Ok(())
    }
    
    pub async fn poll_claude_output(&mut self) -> Result<()> {
        let mut session_ended = false;
        let mut output_lines = Vec::new();
        let mut error_lines = Vec::new();
        
        if let Some(session) = &mut self.claude_session {
            // Read up to 10 lines per poll to avoid blocking
            for _ in 0..10 {
                match session.read_stdout_line().await {
                    Ok(Some(line)) => output_lines.push(line),
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
            
            // Also check stderr for errors
            for _ in 0..5 {
                match session.read_stderr_line().await {
                    Ok(Some(line)) => error_lines.push(line),
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
            
            // Check if process is still running
            if !session.is_running() {
                session_ended = true;
            }
        }
        
        // Display output
        for line in output_lines {
            if !line.trim().is_empty() {
                self.append_output(format!("Claude: {}", line));
            }
        }
        
        // Display errors
        for line in error_lines {
            if !line.trim().is_empty() {
                self.append_output(format!("{} Claude error: {}", prefixes::WARN, line));
            }
        }
        
        if session_ended {
            self.append_output(format!("{} Claude session completed", prefixes::EXEC));
            self.claude_session = None;
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

    pub fn can_cancel(&self) -> bool {
        matches!(self.mode, Mode::Recording | Mode::PlanPending | Mode::ClaudeRunning)
    }
}