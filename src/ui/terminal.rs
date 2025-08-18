use std::io::{stdout, Write};
use anyhow::Result;
use crate::interfaces::UserInterface;
use crate::constants::ERROR_DISPLAY_LIMIT;

pub struct TerminalUI;

impl TerminalUI {
    pub fn new() -> Self {
        Self
    }

    fn print_line(&self, text: &str) -> Result<()> {
        println!("{}", text);
        Ok(())
    }

    fn print_inline(&self, text: &str) -> Result<()> {
        print!("{}", text);
        self.flush()
    }

    fn clear_line(&self) -> Result<()> {
        print!("\r\x1b[K");
        self.flush()
    }

    fn flush(&self) -> Result<()> {
        stdout().flush()?;
        Ok(())
    }
}

impl UserInterface for TerminalUI {
    fn show_recording(&self) -> Result<()> {
        self.print_inline("\r🔴 Recording... (press SPACE to stop)")
    }

    fn show_processing(&self) -> Result<()> {
        self.print_inline("\r⏳ Processing...                     ")
    }

    fn show_success(&self, text: &str) -> Result<()> {
        self.clear_line()?;
        self.print_line("✅ Copied to clipboard\n")?;
        self.print_line(&format!("{}\n", text.trim()))?;
        self.print_inline("Ready (SPACE to record, Q to quit)")
    }

    fn show_error(&self, error: &str) -> Result<()> {
        let truncated = ErrorFormatter::truncate(error, ERROR_DISPLAY_LIMIT);
        self.print_inline(&format!(
            "\r\x1b[K❌ Error: {}. Ready (SPACE to record, Q to quit)",
            truncated
        ))
    }

    fn show_warning(&self, message: &str) -> Result<()> {
        self.print_inline(&format!(
            "\r\x1b[K⚠️  {}. Ready (SPACE to record, Q to quit)",
            message
        ))
    }
}

struct ErrorFormatter;

impl ErrorFormatter {
    fn truncate(text: &str, limit: usize) -> &str {
        if text.len() > limit {
            &text[..limit]
        } else {
            text
        }
    }
}

pub struct WelcomeScreen;

impl WelcomeScreen {
    pub fn display() {
        println!("\n🎤 STT-Clipboard");
        println!("━━━━━━━━━━━━━━━━");
    }
}