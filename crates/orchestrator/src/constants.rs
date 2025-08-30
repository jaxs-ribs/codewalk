pub const MAX_OUTPUT_LINES: usize = 1000;
pub const BLINK_INTERVAL_MS: u64 = 500;
pub const POLL_INTERVAL_MS: u64 = 50;
pub const OVERLAY_WIDTH_PERCENT: u16 = 60;
pub const OVERLAY_HEIGHT_PERCENT: u16 = 40;

pub mod prefixes {
    pub const ASR: &str = "ASR>";
    pub const PLAN: &str = "PLAN>";
    pub const EXEC: &str = "EXEC>";
    pub const WARN: &str = "WARN>";
    pub const UTTERANCE: &str = "UTTERANCE>";
    pub const RELAY: &str = "RELAY>";
}

pub mod messages {
    pub const NO_AUDIO: &str = "no audio captured";
    pub const PLAN_CANCELED: &str = "canceled";
}
