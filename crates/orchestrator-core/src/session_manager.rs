use std::collections::HashMap;
use std::path::PathBuf;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use anyhow::Result;

/// Session information managed by the core
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub prompt: String,
    pub executor_type: String,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub status: SessionStatus,
    pub working_dir: PathBuf,
    pub logs: Vec<SessionLog>,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SessionStatus {
    Active,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionLog {
    pub timestamp: DateTime<Utc>,
    pub log_type: LogType,
    pub content: String,
    pub raw: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LogType {
    UserMessage,
    AssistantMessage,
    ToolCall,
    ToolResult,
    Status,
    Error,
    Info,
}

/// Manages all sessions for the orchestrator
pub struct SessionManager {
    sessions: HashMap<String, Session>,
    current_session_id: Option<String>,
    artifacts_dir: PathBuf,
}

impl SessionManager {
    pub fn new(artifacts_dir: PathBuf) -> Self {
        Self {
            sessions: HashMap::new(),
            current_session_id: None,
            artifacts_dir,
        }
    }
    
    /// Generate a new session ID
    pub fn generate_session_id() -> String {
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
    
    /// Start a new session
    pub fn start_session(&mut self, prompt: String, executor_type: String, working_dir: PathBuf) -> String {
        let session_id = Self::generate_session_id();
        
        let session = Session {
            id: session_id.clone(),
            prompt,
            executor_type,
            started_at: Utc::now(),
            completed_at: None,
            status: SessionStatus::Active,
            working_dir,
            logs: Vec::new(),
            summary: None,
        };
        
        self.sessions.insert(session_id.clone(), session);
        self.current_session_id = Some(session_id.clone());
        
        // Save initial metadata to disk
        self.save_session_metadata(&session_id);
        
        session_id
    }
    
    /// Complete the current session
    pub fn complete_session(&mut self, session_id: &str, summary: Option<String>) {
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.completed_at = Some(Utc::now());
            session.status = SessionStatus::Completed;
            session.summary = summary;
            
            // Save to disk
            self.save_session_to_disk(session_id);
        }
        
        if self.current_session_id.as_ref() == Some(&session_id.to_string()) {
            self.current_session_id = None;
        }
    }
    
    /// Add a log entry to the current session
    pub fn add_log(&mut self, session_id: &str, log_type: LogType, content: String, raw: Option<String>) {
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.logs.push(SessionLog {
                timestamp: Utc::now(),
                log_type,
                content,
                raw,
            });
            
            // Periodically save to disk (every 10 logs)
            if session.logs.len() % 10 == 0 {
                self.save_session_to_disk(session_id);
            }
        }
    }
    
    /// Get the current session
    pub fn current_session(&self) -> Option<&Session> {
        self.current_session_id.as_ref()
            .and_then(|id| self.sessions.get(id))
    }
    
    /// Get a specific session by ID
    pub fn get_session(&self, session_id: &str) -> Option<&Session> {
        self.sessions.get(session_id)
    }
    
    /// Get the last completed session
    pub fn last_completed_session(&self) -> Option<&Session> {
        self.sessions.values()
            .filter(|s| matches!(s.status, SessionStatus::Completed))
            .max_by_key(|s| s.completed_at)
    }
    
    /// Save session metadata to disk
    fn save_session_metadata(&self, session_id: &str) {
        if let Some(session) = self.sessions.get(session_id) {
            let session_dir = self.artifacts_dir.join(session_id);
            if let Err(e) = std::fs::create_dir_all(&session_dir) {
                eprintln!("Failed to create session directory: {}", e);
                return;
            }
            
            let metadata = serde_json::json!({
                "session_id": session.id,
                "prompt": session.prompt,
                "executor_type": session.executor_type,
                "started_at": session.started_at.to_rfc3339(),
                "working_dir": session.working_dir.to_string_lossy(),
                "status": format!("{:?}", session.status),
            });
            
            let metadata_path = session_dir.join("metadata.json");
            if let Ok(content) = serde_json::to_string_pretty(&metadata) {
                let _ = std::fs::write(metadata_path, content);
            }
        }
    }
    
    /// Save full session to disk
    fn save_session_to_disk(&self, session_id: &str) {
        if let Some(session) = self.sessions.get(session_id) {
            let session_dir = self.artifacts_dir.join(session_id);
            if let Err(e) = std::fs::create_dir_all(&session_dir) {
                eprintln!("Failed to create session directory: {}", e);
                return;
            }
            
            // Save full session data
            let session_path = session_dir.join("session.json");
            if let Ok(content) = serde_json::to_string_pretty(&session) {
                let _ = std::fs::write(session_path, content);
            }
            
            // Save human-readable logs
            let logs_path = session_dir.join("logs.txt");
            if let Ok(mut file) = std::fs::File::create(&logs_path) {
                use std::io::Write;
                for log in &session.logs {
                    let _ = writeln!(file, "[{}] {:?}: {}", 
                        log.timestamp.format("%H:%M:%S"),
                        log.log_type,
                        log.content
                    );
                }
            }
        }
    }
    
    /// Load a session from disk
    pub fn load_session_from_disk(&mut self, session_id: &str) -> Result<()> {
        let session_path = self.artifacts_dir.join(session_id).join("session.json");
        let content = std::fs::read_to_string(session_path)?;
        let session: Session = serde_json::from_str(&content)?;
        self.sessions.insert(session_id.to_string(), session);
        Ok(())
    }
}