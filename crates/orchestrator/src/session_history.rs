use std::fs;
use std::path::PathBuf;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use anyhow::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionHistoryEntry {
    pub session_id: String,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub prompt: String,
    pub summary: Option<String>,
    pub status: SessionStatus,
    pub is_resumed: bool,
    pub resumed_from: Option<String>,
    pub executor_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Active,
    Completed,
    Failed,
    Cancelled,
}

pub struct SessionHistory {
    history_file: PathBuf,
    entries: Vec<SessionHistoryEntry>,
}

impl SessionHistory {
    pub fn new(artifacts_dir: &PathBuf) -> Self {
        let history_file = artifacts_dir.join("session_history.json");
        let mut history = Self {
            history_file,
            entries: Vec::new(),
        };
        let _ = history.load();
        history
    }
    
    pub fn add_session(&mut self, entry: SessionHistoryEntry) {
        // Remove any existing entry with same ID (update)
        self.entries.retain(|e| e.session_id != entry.session_id);
        self.entries.push(entry);
        let _ = self.save();
    }
    
    pub fn update_session_status(&mut self, session_id: &str, status: SessionStatus, summary: Option<String>) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.session_id == session_id) {
            entry.status = status;
            entry.completed_at = Some(Utc::now());
            if summary.is_some() {
                entry.summary = summary;
            }
            let _ = self.save();
        }
    }
    
    pub fn get_last_completed(&self) -> Option<&SessionHistoryEntry> {
        self.entries.iter()
            .filter(|e| matches!(e.status, SessionStatus::Completed))
            .max_by_key(|e| e.completed_at)
    }
    
    pub fn get_session(&self, session_id: &str) -> Option<&SessionHistoryEntry> {
        self.entries.iter().find(|e| e.session_id == session_id)
    }
    
    pub fn get_recent(&self, limit: usize) -> Vec<&SessionHistoryEntry> {
        let mut sorted = self.entries.iter().collect::<Vec<_>>();
        sorted.sort_by_key(|e| std::cmp::Reverse(e.started_at));
        sorted.into_iter().take(limit).collect()
    }
    
    fn load(&mut self) -> Result<()> {
        if self.history_file.exists() {
            let content = fs::read_to_string(&self.history_file)?;
            self.entries = serde_json::from_str(&content)?;
        }
        Ok(())
    }
    
    fn save(&self) -> Result<()> {
        let content = serde_json::to_string_pretty(&self.entries)?;
        fs::write(&self.history_file, content)?;
        Ok(())
    }
}