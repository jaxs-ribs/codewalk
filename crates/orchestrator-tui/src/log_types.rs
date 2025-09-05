// Stub types for log display
// These will be replaced with proper control_center integration later

use std::time::SystemTime;

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
    SystemMessage,
    ToolUse,
    ToolResult,
    Error,
    Unknown,
}

impl ParsedLogLine {
    pub fn new(content: String) -> Self {
        Self {
            timestamp: SystemTime::now(),
            entry_type: LogType::Unknown,
            content: content.clone(),
            raw: content,
        }
    }
}