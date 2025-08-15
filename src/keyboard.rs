use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    terminal::{disable_raw_mode, enable_raw_mode},
};
use std::time::Duration;

pub struct KeyboardHandler;

impl KeyboardHandler {
    pub fn enable_raw_mode() -> Result<Self> {
        enable_raw_mode()?;
        Ok(Self)
    }

    pub async fn poll_event(&self) -> Result<Option<KeyAction>> {
        if !event::poll(Duration::from_millis(50))? {
            return Ok(None);
        }

        match event::read()? {
            Event::Key(key) => Ok(Self::process_key(key)),
            _ => Ok(None),
        }
    }

    fn process_key(key: event::KeyEvent) -> Option<KeyAction> {
        if key.kind != KeyEventKind::Press {
            return None;
        }

        match key.code {
            KeyCode::Char(' ') if key.modifiers.is_empty() => {
                Some(KeyAction::ToggleRecording)
            }
            KeyCode::Char('q') | KeyCode::Char('Q') => {
                Some(KeyAction::Quit)
            }
            KeyCode::Char('c') if key.modifiers == KeyModifiers::CONTROL => {
                Some(KeyAction::Quit)
            }
            _ => None,
        }
    }
}

impl Drop for KeyboardHandler {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
    }
}

#[derive(Debug, PartialEq)]
pub enum KeyAction {
    ToggleRecording,
    Quit,
}