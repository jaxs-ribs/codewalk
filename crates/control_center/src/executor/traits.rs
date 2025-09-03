use anyhow::Result;
use async_trait::async_trait;
use std::path::PathBuf;
use crate::logs::ParsedLogLine;

/// Type of executor backend
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum ExecutorType {
    Claude,
    Devin,      // Future
    Codex,      // Future
    Custom(String),
}

impl ExecutorType {
    /// Get human-readable name
    pub fn name(&self) -> &str {
        match self {
            ExecutorType::Claude => "Claude",
            ExecutorType::Devin => "Devin",
            ExecutorType::Codex => "Codex",
            ExecutorType::Custom(name) => name,
        }
    }
    
    /// Filter and extract relevant information from logs for summarization
    /// This is executor-specific to handle different log formats
    pub fn filter_logs_for_summary(&self, logs: &[ParsedLogLine]) -> Vec<String> {
        match self {
            ExecutorType::Claude => Self::filter_claude_logs(logs),
            ExecutorType::Devin => Self::filter_devin_logs(logs),
            ExecutorType::Codex => Self::filter_codex_logs(logs),
            ExecutorType::Custom(_) => Self::filter_generic_logs(logs),
        }
    }
    
    /// Claude Code-specific log filtering
    /// Extracts:
    /// - User prompts (from initial messages)
    /// - Assistant responses (text only, not tool calls)
    /// - Tool names used (without full JSON)
    /// - Tool results (success/failure/key outputs)
    /// - Errors
    fn filter_claude_logs(logs: &[ParsedLogLine]) -> Vec<String> {
        let mut filtered = Vec::new();
        
        for log in logs {
            // Try to parse the content as JSON (Claude Code logs are JSON)
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&log.content) {
                // Extract based on log type
                if let Some(log_type) = json.get("type").and_then(|t| t.as_str()) {
                    match log_type {
                        "user" => {
                            // Extract user messages (initial prompts)
                            if let Some(message) = json.get("message") {
                                if let Some(content) = message.get("content") {
                                    if let Some(arr) = content.as_array() {
                                        for item in arr {
                                            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                                // Skip tool results, only get actual user input
                                                if !item.get("type").map_or(false, |t| t == "tool_result") {
                                                    filtered.push(format!("User: {}", Self::truncate_text(text, 200)));
                                                }
                                            } else if let Some(tool_result) = item.get("type").and_then(|t| t.as_str()) {
                                                if tool_result == "tool_result" {
                                                    // Extract concise tool result info
                                                    if let Some(content) = item.get("content").and_then(|c| c.as_str()) {
                                                        let summary = Self::summarize_tool_result(content);
                                                        if !summary.is_empty() {
                                                            filtered.push(format!("• {}", summary));
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        "assistant" => {
                            // Extract assistant text responses and tool usage
                            if let Some(message) = json.get("message") {
                                if let Some(content) = message.get("content") {
                                    if let Some(arr) = content.as_array() {
                                        for item in arr {
                                            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                                // Assistant's text response
                                                filtered.push(format!("Claude: {}", Self::truncate_text(text, 150)));
                                            } else if let Some(tool_use) = item.get("type").and_then(|t| t.as_str()) {
                                                if tool_use == "tool_use" {
                                                    // Extract tool name and brief description
                                                    if let Some(name) = item.get("name").and_then(|n| n.as_str()) {
                                                        if let Some(input) = item.get("input") {
                                                            let tool_desc = Self::describe_tool_use(name, input);
                                                            filtered.push(format!("→ {}", tool_desc));
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        "error" => {
                            // Extract error messages
                            if let Some(msg) = json.get("message").and_then(|m| m.as_str()) {
                                filtered.push(format!("ERROR: {}", Self::truncate_text(msg, 100)));
                            }
                        },
                        _ => {} // Skip other types like "system" init messages
                    }
                }
            } else if matches!(log.entry_type, crate::logs::LogType::Error) {
                // Non-JSON error logs
                filtered.push(format!("Error: {}", Self::truncate_text(&log.content, 100)));
            }
        }
        
        filtered
    }
    
    /// Placeholder for Devin log filtering
    fn filter_devin_logs(logs: &[ParsedLogLine]) -> Vec<String> {
        // TODO: Implement when Devin integration is added
        Self::filter_generic_logs(logs)
    }
    
    /// Placeholder for Codex log filtering
    fn filter_codex_logs(logs: &[ParsedLogLine]) -> Vec<String> {
        // TODO: Implement when Codex integration is added
        Self::filter_generic_logs(logs)
    }
    
    /// Generic fallback filter for unknown executors
    fn filter_generic_logs(logs: &[ParsedLogLine]) -> Vec<String> {
        logs.iter()
            .filter(|log| matches!(
                log.entry_type,
                crate::logs::LogType::UserMessage | 
                crate::logs::LogType::AssistantMessage |
                crate::logs::LogType::Error
            ))
            .map(|log| Self::truncate_text(&log.content, 150).to_string())
            .collect()
    }
    
    /// Helper: Truncate text to max length with ellipsis
    fn truncate_text(text: &str, max_len: usize) -> &str {
        if text.len() <= max_len {
            text
        } else {
            &text[..max_len.min(text.len())]
        }
    }
    
    /// Helper: Create concise description of tool usage
    fn describe_tool_use(tool_name: &str, input: &serde_json::Value) -> String {
        match tool_name {
            "Write" | "MultiEdit" => {
                if let Some(path) = input.get("file_path").and_then(|p| p.as_str()) {
                    format!("{} {}", tool_name, path.split('/').last().unwrap_or(path))
                } else {
                    tool_name.to_string()
                }
            },
            "Read" => {
                if let Some(path) = input.get("file_path").and_then(|p| p.as_str()) {
                    format!("Read {}", path.split('/').last().unwrap_or(path))
                } else {
                    "Read file".to_string()
                }
            },
            "Bash" => {
                if let Some(cmd) = input.get("command").and_then(|c| c.as_str()) {
                    format!("Run: {}", Self::truncate_text(cmd, 50))
                } else {
                    "Run command".to_string()
                }
            },
            "Glob" | "Grep" => {
                if let Some(pattern) = input.get("pattern").and_then(|p| p.as_str()) {
                    format!("{} '{}'", tool_name, Self::truncate_text(pattern, 30))
                } else {
                    tool_name.to_string()
                }
            },
            "Task" => {
                if let Some(desc) = input.get("description").and_then(|d| d.as_str()) {
                    format!("Task: {}", desc)
                } else {
                    "Launch task".to_string()
                }
            },
            _ => tool_name.to_string()
        }
    }
    
    /// Helper: Summarize tool results concisely
    fn summarize_tool_result(content: &str) -> String {
        let lines: Vec<&str> = content.lines().collect();
        
        // Check for common patterns
        if content.contains("No files found") || content.contains("No matches") {
            return "No results".to_string();
        }
        
        if content.starts_with("File created") || content.starts_with("File updated") {
            return content.lines().next().unwrap_or("File changed").to_string();
        }
        
        if content.contains("error") || content.contains("Error") {
            // Extract first error line
            if let Some(error_line) = lines.iter().find(|l| l.contains("error") || l.contains("Error")) {
                return format!("Error: {}", Self::truncate_text(error_line, 80));
            }
        }
        
        // For file listings, count files
        if lines.len() > 5 && lines.iter().all(|l| l.starts_with('/') || l.starts_with("./")) {
            return format!("Found {} files", lines.len());
        }
        
        // Default: first line or truncated content
        if let Some(first) = lines.first() {
            Self::truncate_text(first, 100).to_string()
        } else {
            String::new()
        }
    }
}

/// Configuration for an executor session
#[derive(Debug, Clone)]
pub struct ExecutorConfig {
    /// Working directory for the executor
    pub working_dir: PathBuf,
    /// Optional log directory
    #[allow(dead_code)]
    pub log_dir: Option<PathBuf>,
    /// Whether to skip permission prompts
    pub skip_permissions: bool,
    /// Custom flags for the executor
    pub custom_flags: Vec<String>,
}

impl Default for ExecutorConfig {
    fn default() -> Self {
        Self {
            working_dir: PathBuf::from("~/Documents/walking-projects/first"),
            log_dir: Some(PathBuf::from("~/Documents/walking-projects/logs")),
            skip_permissions: true,
            custom_flags: Vec::new(),
        }
    }
}

/// Output from an executor
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum ExecutorOutput {
    Stdout(String),
    Stderr(String),
    Status(String),
    Progress(f32, String), // Progress percentage and message
}

/// Trait for code executor sessions (Claude, Devin, etc.)
#[async_trait]
pub trait ExecutorSession: Send {
    /// Get the executor type
    #[allow(dead_code)]
    fn executor_type(&self) -> ExecutorType;
    
    /// Get the session ID (if available)
    fn session_id(&self) -> Option<String>;
    
    /// Launch the executor with a prompt
    async fn launch(prompt: &str, config: ExecutorConfig) -> Result<Box<dyn ExecutorSession>>
    where
        Self: Sized;
    
    /// Read next output from the executor (non-blocking)
    async fn read_output(&mut self) -> Result<Option<ExecutorOutput>>;
    
    /// Check if the executor is still running
    fn is_running(&mut self) -> bool;
    
    /// Send input to the executor (if supported)
    #[allow(dead_code)]
    async fn send_input(&mut self, _input: &str) -> Result<()> {
        Err(anyhow::anyhow!("Input not supported by this executor"))
    }
    
    /// Terminate the executor session
    async fn terminate(&mut self) -> Result<()>;
    
    /// Get session metadata
    #[allow(dead_code)]
    fn get_metadata(&self) -> Option<serde_json::Value> {
        None
    }
}

