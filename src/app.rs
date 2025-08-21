use anyhow::Result;
use std::time::Duration;

use crate::backend::{self, PlanInfo};
use crate::constants::{self, messages, prefixes};
use crate::types::{Mode, PlanState, RecordingState};

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    pub recording: RecordingState,
}

impl App {
    pub fn new() -> Self {
        Self {
            output: Vec::new(),
            input: String::new(),
            mode: Mode::Idle,
            plan: PlanState::new(),
            recording: RecordingState::new(),
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

    pub fn start_recording(&mut self) -> Result<()> {
        self.mode = Mode::Recording;
        self.recording.start();
        backend::record_voice(true)?;
        Ok(())
    }

    pub fn stop_recording(&mut self) -> Result<()> {
        backend::record_voice(false)?;
        let audio = backend::take_recorded_audio()?;
        
        if audio.is_empty() {
            self.handle_empty_recording();
        } else {
            self.process_audio(audio)?;
        }
        
        self.recording.stop();
        Ok(())
    }

    fn handle_empty_recording(&mut self) {
        self.append_output(format!("{} {}", prefixes::ASR, messages::NO_AUDIO));
        self.mode = Mode::Idle;
    }

    fn process_audio(&mut self, audio: Vec<u8>) -> Result<()> {
        let utterance = backend::voice_to_text(audio)?;
        self.append_output(format!("{} {}", prefixes::ASR, utterance));
        self.create_plan(&utterance)?;
        Ok(())
    }

    pub fn create_plan(&mut self, text: &str) -> Result<()> {
        let plan_json = backend::text_to_llm_cmd(text)?;
        let plan_info = backend::parse_plan_json(&plan_json).ok();
        
        if let Some(info) = plan_info {
            self.handle_plan_response(info, plan_json)?;
        } else {
            self.handle_invalid_plan();
        }
        
        Ok(())
    }

    fn handle_plan_response(&mut self, info: PlanInfo, json: String) -> Result<()> {
        match info.status.as_str() {
            "ok" if info.has_steps => {
                let cmd = backend::extract_cmd(&json)?;
                self.plan.set(json.clone(), cmd);
                self.mode = Mode::PlanPending;
                self.append_output(format!("{} {}", prefixes::PLAN, json));
            }
            "deny" => {
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
            _ => {}
        }
    }

    pub fn handle_text_input(&mut self) -> Result<()> {
        if !self.input.is_empty() {
            let text = self.input.clone();
            self.append_output(format!("{} {}", prefixes::UTTERANCE, text));
            self.input.clear();
            self.create_plan(&text)?;
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
        matches!(self.mode, Mode::Recording | Mode::PlanPending)
    }
}