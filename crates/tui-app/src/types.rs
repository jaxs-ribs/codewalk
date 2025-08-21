use std::time::Instant;

#[derive(Debug, Clone, PartialEq)]
pub enum Mode {
    Idle,
    Recording,
    PlanPending,
    Executing,
}

pub struct RecordingState {
    pub is_active: bool,
    pub started_at: Option<Instant>,
    pub blink_state: bool,
    pub last_blink: Instant,
}

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

pub struct PlanState {
    pub json: Option<String>,
    pub command: Option<String>,
}

impl PlanState {
    pub fn new() -> Self {
        Self {
            json: None,
            command: None,
        }
    }

    pub fn set(&mut self, json: String, command: String) {
        self.json = Some(json);
        self.command = Some(command);
    }

    pub fn clear(&mut self) {
        self.json = None;
        self.command = None;
    }

    pub fn is_pending(&self) -> bool {
        self.json.is_some()
    }
}