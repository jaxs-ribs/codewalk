use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use tokio::fs;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use notify::{Watcher, RecursiveMode, Event, EventKind};

// Default Claude logs directory; prefer workspace-local path to keep artifacts together
const CLAUDE_LOGS_DIR: &str = "artifacts/executor_logs";
const POLL_INTERVAL_MS: u64 = 100;

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

/// Abstract log monitor trait
#[async_trait::async_trait]
pub trait LogMonitor: Send {
    async fn start(&mut self) -> Result<()>;
}

/// Implementation that reads Claude Code JSONL files
pub struct ClaudeLogMonitor {
    log_dir: PathBuf,
    session_dir: Option<PathBuf>,
    tx: mpsc::Sender<ParsedLogLine>,
    last_position: usize,
    current_file: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LogEntry {
    #[serde(rename = "type")]
    entry_type: String,
    timestamp: Option<String>,
    content: Option<serde_json::Value>,
    tool: Option<String>,
    role: Option<String>,
    message: Option<String>,
}

impl ClaudeLogMonitor {
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

    fn log_type_from_entry(entry: &LogEntry) -> LogType {
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
    
    fn parse_log_line(&self, line: &str) -> Result<ParsedLogLine> {
        let entry: LogEntry = serde_json::from_str(line)?;
        let log_type = Self::log_type_from_entry(&entry);
        
        // Extract content based on type
        let content = self.extract_content(&entry);
        
        Ok(ParsedLogLine {
            timestamp: SystemTime::now(),
            entry_type: log_type,
            content,
            raw: line.to_string(),
        })
    }
    
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
                // Check for text field
                if let Some(text) = obj.get("text").and_then(|v| v.as_str()) {
                    return text.to_string();
                }
                
                // Check for message field
                if let Some(msg) = obj.get("message").and_then(|v| v.as_str()) {
                    return msg.to_string();
                }
                
                // Special handling for tool calls/results
                if let Some(tool_name) = obj.get("tool_name").and_then(|v| v.as_str()) {
                    if let Some(tool_input) = obj.get("tool_input") {
                        // Extract key info from tool input
                        if let Some(input_obj) = tool_input.as_object() {
                            if tool_name.contains("Write") || tool_name.contains("Edit") {
                                if let Some(file) = input_obj.get("file_path").and_then(|v| v.as_str()) {
                                    return format!("{}: {}", tool_name, file);
                                }
                            } else if tool_name.contains("Read") {
                                if let Some(file) = input_obj.get("file_path").and_then(|v| v.as_str()) {
                                    return format!("Reading: {}", file);
                                }
                            } else if tool_name.contains("Bash") {
                                if let Some(cmd) = input_obj.get("command").and_then(|v| v.as_str()) {
                                    let short_cmd = if cmd.len() > 50 {
                                        format!("{}...", &cmd[..50])
                                    } else {
                                        cmd.to_string()
                                    };
                                    return format!("$ {}", short_cmd);
                                }
                            }
                        }
                        return format!("{}", tool_name);
                    }
                    return format!("{}", tool_name);
                }
                
                // Handle tool results
                if let Some(output) = obj.get("output") {
                    if let Some(text) = output.as_str() {
                        let lines: Vec<&str> = text.lines().take(2).collect();
                        if lines.len() > 1 {
                            return format!("{}...", lines[0]);
                        } else if !lines.is_empty() {
                            return lines[0].to_string();
                        }
                    }
                }
                
                // Handle status messages
                if let Some(status) = obj.get("status").and_then(|v| v.as_str()) {
                    return status.to_string();
                }
            }
            
            // For arrays, try to summarize
            if let Some(arr) = content.as_array() {
                if !arr.is_empty() {
                    if let Some(first) = arr.first() {
                        if let Some(text) = first.as_str() {
                            return text.to_string();
                        }
                    }
                    return format!("[{} items]", arr.len());
                }
            }
            
            // Last resort - try to get a concise string representation
            if let Ok(compact) = serde_json::to_string(content) {
                if compact.len() <= 100 {
                    return compact;
                } else {
                    return format!("{}...", &compact[..100]);
                }
            }
        }
        
        // Handle tool calls
        if let Some(tool) = &entry.tool {
            return format!("Tool: {}", tool);
        }
        
        // Default
        format!("[{}]", entry.entry_type)
    }
    
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

#[async_trait::async_trait]
impl LogMonitor for ClaudeLogMonitor {
    async fn start(&mut self) -> Result<()> {
        // First, try to find the latest session file
        self.find_latest_session().await?;
        
        // Set up file watcher
        let (watcher_tx, mut watcher_rx) = mpsc::channel(100);
        let watch_path = self.session_dir.as_ref().unwrap_or(&self.log_dir);
        
        // Spawn file watcher in background
        let watch_path_clone = watch_path.clone();
        tokio::spawn(async move {
            let _ = Self::watch_directory(&watch_path_clone, watcher_tx).await;
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
}

/// Create a log monitoring task (Claude-only default)
pub fn spawn_log_monitor(working_dir: Option<&Path>) -> mpsc::Receiver<ParsedLogLine> {
    let (tx, rx) = mpsc::channel(100);
    
    let mut monitor = if let Some(dir) = working_dir {
        ClaudeLogMonitor::with_working_dir(dir, tx)
    } else {
        ClaudeLogMonitor::new(tx)
    };
    
    tokio::spawn(async move {
        if let Err(e) = monitor.start().await {
            eprintln!("Log monitor error: {}", e);
        }
    });
    
    rx
}
