use anyhow::Result;
use control_center::{ParsedLogLine, logs::LogType};

/// Summarizes session logs using Groq API
pub struct LogSummarizer {
    initialized: bool,
}

impl LogSummarizer {
    pub fn new() -> Self {
        Self { initialized: false }
    }

    pub fn initialize(&mut self) -> Result<()> {
        self.initialized = true;
        Ok(())
    }

    /// Summarize session logs into a concise voice-friendly summary
    pub async fn summarize_logs(&self, logs: &[ParsedLogLine]) -> Result<String> {
        if logs.is_empty() {
            return Ok("No activity to summarize".to_string());
        }

        // Format logs into readable text
        let formatted_logs = logs.iter()
            .filter_map(|log| {
                // Filter out noise, keep important events
                match &log.entry_type {
                    LogType::UserMessage => {
                        Some(format!("• User: {}", log.content.chars().take(100).collect::<String>()))
                    }
                    LogType::AssistantMessage => {
                        Some(format!("• Claude: {}", log.content.chars().take(100).collect::<String>()))
                    }
                    LogType::ToolCall => {
                        Some(format!("• Tool: {}", log.content.chars().take(100).collect::<String>()))
                    }
                    LogType::ToolResult if log.content.contains("error") => {
                        Some(format!("• Error: {}", log.content.chars().take(100).collect::<String>()))
                    }
                    LogType::Error => {
                        Some(format!("• Error: {}", log.content))
                    }
                    _ => None,
                }
            })
            .take(20) // Limit to recent important events
            .collect::<Vec<_>>()
            .join("\n");

        if formatted_logs.trim().is_empty() {
            return Ok("Claude is working on the task".to_string());
        }

        let system_prompt = r#"You are a concise assistant summarizing a Claude Code session for voice output.
Write in PRESENT TENSE as if reporting live activity.
Be conversational but informative.

Rules:
• Start with what Claude is currently doing (1 sentence)
• List 2-3 key actions or files being worked on
• Keep total under 100 words
• Use simple language suitable for speech
• No technical jargon unless necessary"#;

        let user_prompt = format!("Summarize this Claude Code activity:\n\n{}", formatted_logs);

        // Call backend's LLM summarizer
        let summary = crate::backend::summarize_with_groq(&system_prompt, &user_prompt).await?;
        
        // Clean up the summary for speech
        let cleaned = summary
            .replace("Claude Code", "Claude")
            .replace("```", "")
            .trim()
            .to_string();

        Ok(cleaned)
    }
}