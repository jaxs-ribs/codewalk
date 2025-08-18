use anyhow::{Result, anyhow};
use crate::interfaces::ClipboardService;
use std::process::Command;

pub struct SystemClipboardService;

impl SystemClipboardService {
    pub fn new() -> Self {
        Self
    }
}

impl ClipboardService for SystemClipboardService {
    fn copy_to_clipboard(&self, text: &str) -> Result<()> {
        ClipboardCommand::execute(text)
    }
}

struct ClipboardCommand;

impl ClipboardCommand {
    fn execute(text: &str) -> Result<()> {
        let mut child = Self::spawn_pbcopy()?;
        Self::write_to_stdin(&mut child, text)?;
        Self::wait_for_completion(child)
    }

    fn spawn_pbcopy() -> Result<std::process::Child> {
        Command::new("pbcopy")
            .stdin(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| anyhow!("Failed to spawn pbcopy: {}", e))
    }

    fn write_to_stdin(child: &mut std::process::Child, text: &str) -> Result<()> {
        use std::io::Write;
        
        let stdin = child
            .stdin
            .as_mut()
            .ok_or_else(|| anyhow!("Failed to open stdin"))?;
        
        stdin
            .write_all(text.as_bytes())
            .map_err(|e| anyhow!("Failed to write to clipboard: {}", e))
    }

    fn wait_for_completion(child: std::process::Child) -> Result<()> {
        let output = child
            .wait_with_output()
            .map_err(|e| anyhow!("Failed to wait for pbcopy: {}", e))?;
        
        if !output.status.success() {
            return Err(anyhow!("pbcopy failed with status: {}", output.status));
        }
        
        Ok(())
    }
}