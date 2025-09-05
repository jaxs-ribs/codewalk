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

#[allow(dead_code)]
pub struct SessionHistory {
    history_file: PathBuf,
    entries: Vec<SessionHistoryEntry>,
}

#[allow(dead_code)]
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

// Standalone functions for App compatibility

/// Load the last session from disk
pub fn load_last_session(artifacts_dir: &PathBuf) -> Option<(String, String)> {
    let session_dir = artifacts_dir.join(".last_session");
    if !session_dir.exists() {
        return None;
    }
    
    let id_path = session_dir.join("id");
    let summary_path = session_dir.join("summary");
    
    if let (Ok(id), Ok(summary)) = (fs::read_to_string(id_path), fs::read_to_string(summary_path)) {
        Some((id.trim().to_string(), summary.trim().to_string()))
    } else {
        None
    }
}

/// Save session status to disk
pub fn save_session_status(artifacts_dir: &PathBuf, session_id: &str, summary: &str, status: &str) {
    let session_dir = artifacts_dir.join(session_id);
    if let Err(e) = fs::create_dir_all(&session_dir) {
        eprintln!("Failed to create session directory: {}", e);
        return;
    }
    
    let status_path = session_dir.join("status.json");
    let status_data = serde_json::json!({
        "session_id": session_id,
        "summary": summary,
        "status": status,
        "updated_at": Utc::now().to_rfc3339(),
    });
    
    if let Ok(content) = serde_json::to_string_pretty(&status_data) {
        let _ = fs::write(status_path, content);
    }
    
    // Also save as last session if completed
    if status == "completed" {
        let last_dir = artifacts_dir.join(".last_session");
        if let Ok(()) = fs::create_dir_all(&last_dir) {
            let _ = fs::write(last_dir.join("id"), session_id);
            let _ = fs::write(last_dir.join("summary"), summary);
        }
    }
}

/// Load session summary from disk
pub fn load_session_summary(artifacts_dir: &PathBuf, session_id: &str) -> Option<String> {
    let status_path = artifacts_dir.join(session_id).join("status.json");
    if let Ok(content) = fs::read_to_string(status_path) {
        if let Ok(data) = serde_json::from_str::<serde_json::Value>(&content) {
            return data.get("summary").and_then(|s| s.as_str()).map(|s| s.to_string());
        }
    }
    None
}
