use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use tokio::fs;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use notify::{Watcher, RecursiveMode, Event, EventKind};

const CLAUDE_LOGS_DIR: &str = "~/.claude/projects";
const POLL_INTERVAL_MS: u64 = 100;

/// Represents a single log entry from Claude
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    #[serde(rename = "type")]
    pub entry_type: String,
    pub timestamp: Option<String>,
    pub content: Option<serde_json::Value>,
    pub tool: Option<String>,
    pub role: Option<String>,
    pub message: Option<String>,
}

/// Represents a parsed log line with metadata
#[derive(Debug, Clone)]
pub struct ParsedLogLine {
    pub timestamp: SystemTime,
    pub entry_type: LogType,
    pub content: String,
    pub raw: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LogType {
    UserMessage,
    AssistantMessage,
    ToolCall,
    ToolResult,
    Status,
    Error,
    Unknown,
}

impl LogType {
    fn from_entry(entry: &LogEntry) -> Self {
        match entry.entry_type.as_str() {
            "user" | "user_message" => LogType::UserMessage,
            "assistant" | "assistant_message" => LogType::AssistantMessage,
            "tool_call" | "tool_use" => LogType::ToolCall,
            "tool_result" | "tool_response" => LogType::ToolResult,
            "status" => LogType::Status,
            "error" => LogType::Error,
            _ => LogType::Unknown,
        }
    }
}

pub struct LogMonitor {
    log_dir: PathBuf,
    session_dir: Option<PathBuf>,
    tx: mpsc::Sender<ParsedLogLine>,
    last_position: usize,
    current_file: Option<PathBuf>,
}

impl LogMonitor {
    /// Create a new log monitor
    pub fn new(tx: mpsc::Sender<ParsedLogLine>) -> Self {
        let log_dir = Self::expand_tilde(Path::new(CLAUDE_LOGS_DIR));
        
        Self {
            log_dir,
            session_dir: None,
            tx,
            last_position: 0,
            current_file: None,
        }
    }
    
    /// Create a monitor for a specific working directory
    pub fn with_working_dir(working_dir: &Path, tx: mpsc::Sender<ParsedLogLine>) -> Self {
        let mut monitor = Self::new(tx);
        
        // Try to find or create a logs directory in the working directory
        let logs_dir = working_dir.join("logs");
        if logs_dir.exists() || std::fs::create_dir_all(&logs_dir).is_ok() {
            monitor.session_dir = Some(logs_dir);
        }
        
        monitor
    }
    
    /// Start monitoring for new log entries
    pub async fn start(&mut self) -> Result<()> {
        // First, try to find the latest session file
        self.find_latest_session().await?;
        
        // Set up file watcher
        let (watcher_tx, mut watcher_rx) = mpsc::channel(100);
        let watch_path = self.session_dir.as_ref().unwrap_or(&self.log_dir);
        
        // Spawn file watcher in background
        let watch_path_clone = watch_path.clone();
        tokio::spawn(async move {
            Self::watch_directory(&watch_path_clone, watcher_tx).await
        });
        
        // Main monitoring loop
        let mut poll_interval = interval(Duration::from_millis(POLL_INTERVAL_MS));
        
        loop {
            tokio::select! {
                _ = poll_interval.tick() => {
                    // Poll current file for changes
                    if let Err(e) = self.check_current_file().await {
                        eprintln!("Error checking log file: {}", e);
                    }
                }
                
                Some(_event) = watcher_rx.recv() => {
                    // File system event - check for new files
                    if let Err(e) = self.find_latest_session().await {
                        eprintln!("Error finding session: {}", e);
                    }
                }
            }
        }
    }
    
    /// Find the latest Claude session log file
    async fn find_latest_session(&mut self) -> Result<()> {
        let search_dir = self.session_dir.as_ref().unwrap_or(&self.log_dir);
        
        // Look for JSONL files
        let mut entries = fs::read_dir(search_dir).await?;
        let mut latest_file: Option<(PathBuf, SystemTime)> = None;
        
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            
            // Check if it's a JSONL file
            if path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                if let Ok(metadata) = entry.metadata().await {
                    if let Ok(modified) = metadata.modified() {
                        if latest_file.as_ref().map_or(true, |(_, time)| modified > *time) {
                            latest_file = Some((path, modified));
                        }
                    }
                }
            }
        }
        
        if let Some((path, _)) = latest_file {
            if self.current_file.as_ref() != Some(&path) {
                // New file found
                self.current_file = Some(path);
                self.last_position = 0;
            }
        }
        
        Ok(())
    }
    
    /// Check current file for new content
    async fn check_current_file(&mut self) -> Result<()> {
        if let Some(file_path) = &self.current_file {
            let content = fs::read_to_string(file_path).await?;
            let lines: Vec<&str> = content.lines().collect();
            
            // Process new lines
            for (_i, line) in lines.iter().enumerate().skip(self.last_position) {
                if !line.trim().is_empty() {
                    if let Ok(parsed) = self.parse_log_line(line) {
                        // Send to channel (ignore if receiver dropped)
                        let _ = self.tx.send(parsed).await;
                    }
                }
            }
            
            self.last_position = lines.len();
        }
        
        Ok(())
    }
    
    /// Parse a single JSONL log line
    fn parse_log_line(&self, line: &str) -> Result<ParsedLogLine> {
        let entry: LogEntry = serde_json::from_str(line)?;
        let log_type = LogType::from_entry(&entry);
        
        // Extract content based on type
        let content = self.extract_content(&entry);
        
        Ok(ParsedLogLine {
            timestamp: SystemTime::now(),
            entry_type: log_type,
            content,
            raw: line.to_string(),
        })
    }
    
    /// Extract human-readable content from log entry
    fn extract_content(&self, entry: &LogEntry) -> String {
        // Try to extract message
        if let Some(msg) = &entry.message {
            return msg.clone();
        }
        
        // Try to extract content
        if let Some(content) = &entry.content {
            // Handle different content structures
            if let Some(text) = content.as_str() {
                return text.to_string();
            }
            
            // Try to get text field from object
            if let Some(obj) = content.as_object() {
                if let Some(text) = obj.get("text").and_then(|v| v.as_str()) {
                    return text.to_string();
                }
                if let Some(msg) = obj.get("message").and_then(|v| v.as_str()) {
                    return msg.to_string();
                }
            }
            
            // Fallback to JSON representation
            return serde_json::to_string_pretty(content).unwrap_or_default();
        }
        
        // Handle tool calls
        if let Some(tool) = &entry.tool {
            return format!("Tool: {}", tool);
        }
        
        // Default
        format!("[{}]", entry.entry_type)
    }
    
    /// Watch a directory for changes
    async fn watch_directory(path: &Path, tx: mpsc::Sender<()>) -> Result<()> {
        let (notify_tx, mut notify_rx) = mpsc::channel(100);
        
        let mut watcher = notify::recommended_watcher(move |res: Result<Event, notify::Error>| {
            if let Ok(event) = res {
                if matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_)) {
                    let _ = notify_tx.blocking_send(());
                }
            }
        })?;
        
        watcher.watch(path, RecursiveMode::NonRecursive)?;
        
        while notify_rx.recv().await.is_some() {
            let _ = tx.send(()).await;
        }
        
        Ok(())
    }
    
    /// Expand tilde in path
    fn expand_tilde(path: &Path) -> PathBuf {
        if let Some(path_str) = path.to_str() {
            if path_str.starts_with("~/") {
                if let Some(home) = std::env::var_os("HOME") {
                    let mut expanded = PathBuf::from(home);
                    expanded.push(&path_str[2..]);
                    return expanded;
                }
            }
        }
        path.to_path_buf()
    }
}

/// Create a log monitoring task
pub fn spawn_log_monitor(working_dir: Option<&Path>) -> mpsc::Receiver<ParsedLogLine> {
    let (tx, rx) = mpsc::channel(100);
    
    let mut monitor = if let Some(dir) = working_dir {
        LogMonitor::with_working_dir(dir, tx)
    } else {
        LogMonitor::new(tx)
    };
    
    tokio::spawn(async move {
        if let Err(e) = monitor.start().await {
            eprintln!("Log monitor error: {}", e);
        }
    });
    
    rx
}