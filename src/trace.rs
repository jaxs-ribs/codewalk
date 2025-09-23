use std::{
    cell::Cell,
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
};

use anyhow::{Context, Result};
use chrono::{Local, SecondsFormat, Utc};
use serde::Serialize;

#[derive(Serialize)]
pub struct TraceEntry {
    pub id: String,
    pub timestamp: String,
    pub mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assistant_text: Option<String>,
    pub durations: TraceDurations,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tts: Option<TraceTts>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub errors: Vec<String>,
}

impl TraceEntry {
    pub fn new(mode: &str) -> Self {
        Self {
            id: String::new(),
            timestamp: String::new(),
            mode: mode.to_string(),
            user_text: None,
            assistant_text: None,
            durations: TraceDurations::default(),
            tts: None,
            errors: Vec::new(),
        }
    }
}

#[derive(Default, Serialize)]
pub struct TraceDurations {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub record_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stt_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub llm_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tts_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speak_ms: Option<u64>,
}

#[derive(Serialize)]
pub struct TraceTts {
    pub engine: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub voice: String,
    pub content_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

pub struct TraceLogger {
    enabled: bool,
    base_dir: PathBuf,
    counter: Cell<u32>,
}

impl TraceLogger {
    pub fn new(logging_enabled: bool) -> Result<Option<Self>> {
        if !logging_enabled {
            return Ok(None);
        }

        let base_dir = PathBuf::from("logs");
        fs::create_dir_all(&base_dir).context("Failed to create logs directory")?;

        Ok(Some(Self {
            enabled: logging_enabled,
            base_dir,
            counter: Cell::new(0),
        }))
    }

    fn next_id(&self) -> String {
        let seq = self.counter.get();
        self.counter.set(seq + 1);
        format!("{}-{:04}", Utc::now().format("%Y%m%dT%H%M%S"), seq)
    }

    pub fn log(&self, mut entry: TraceEntry) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        entry.id = self.next_id();
        entry.timestamp = Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true);
        let date = Local::now().format("%Y%m%d").to_string();
        let path = self.base_dir.join(format!("trace-{date}.jsonl"));
        let json = serde_json::to_string(&entry).context("Failed to serialize trace entry")?;

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .with_context(|| format!("Failed to open trace log file at {}", path.display()))?;
        file.write_all(json.as_bytes())
            .context("Failed to write trace entry")?;
        file.write_all(b"\n")
            .context("Failed to finalize trace entry")?;
        Ok(())
    }
}
