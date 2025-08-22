use anyhow::Result;
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

use crate::app::App;
use crate::types::{Mode, ScrollDirection};

pub struct InputHandler;

impl InputHandler {
    pub async fn handle_key(app: &mut App, key: KeyEvent) -> Result<bool> {
        if !Self::is_valid_event(key) {
            return Ok(false);
        }

        // Check for Ctrl+C to quit
        if key.code == KeyCode::Char('c') && key.modifiers == KeyModifiers::CONTROL {
            return Ok(true); // Quit signal
        }

        Self::process_key(app, key).await?;
        Ok(false)
    }

    fn is_valid_event(key: KeyEvent) -> bool {
        matches!(key.kind, KeyEventKind::Press)
    }

    async fn process_key(app: &mut App, key: KeyEvent) -> Result<()> {
        if key.kind == KeyEventKind::Press {
            Self::handle_key_press(app, key).await?;
        }
        Ok(())
    }

    async fn handle_key_press(app: &mut App, key: KeyEvent) -> Result<()> {
        // Handle scrolling controls first (work in most modes)
        match (key.code, key.modifiers) {
            // Scrolling controls
            (KeyCode::Up, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::Up, 1);
                return Ok(());
            }
            (KeyCode::Down, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::Down, 1);
                return Ok(());
            }
            (KeyCode::PageUp, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::PageUp, 10);
                return Ok(());
            }
            (KeyCode::PageDown, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::PageDown, 10);
                return Ok(());
            }
            (KeyCode::Home, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::Home, 0);
                return Ok(());
            }
            (KeyCode::End, _) if app.mode != Mode::Recording => {
                app.handle_scroll(ScrollDirection::End, 0);
                return Ok(());
            }
            _ => {}
        }
        
        // Handle mode-specific keys
        match (key.code, key.modifiers) {
            (KeyCode::Char('r'), KeyModifiers::CONTROL) => Self::handle_record_toggle(app).await?,
            (KeyCode::Enter, _) => Self::handle_enter(app).await?,
            (KeyCode::Esc, _) => Self::handle_cancel(app),
            (KeyCode::Char('n'), KeyModifiers::NONE) if app.mode == Mode::PlanPending => {
                Self::handle_cancel(app)
            }
            (KeyCode::Char(c), KeyModifiers::NONE | KeyModifiers::SHIFT) => {
                Self::handle_character_input(app, c)
            }
            (KeyCode::Backspace, _) => Self::handle_backspace(app),
            _ => {}
        }
        Ok(())
    }

    async fn handle_record_toggle(app: &mut App) -> Result<()> {
        if app.can_start_recording() {
            app.start_recording().await?;
        } else if app.can_stop_recording() {
            app.stop_recording().await?;
        }
        Ok(())
    }

    async fn handle_enter(app: &mut App) -> Result<()> {
        match app.mode {
            Mode::Idle => app.handle_text_input().await?,
            Mode::ConfirmingExecutor => app.confirm_executor().await?,
            Mode::ShowingError => app.dismiss_error(),
            _ => {}
        }
        Ok(())
    }

    fn handle_cancel(app: &mut App) {
        if app.can_cancel() {
            app.cancel_current_operation();
        }
    }

    fn handle_character_input(app: &mut App, c: char) {
        if app.can_edit_input() {
            app.input.push(c);
        }
    }

    fn handle_backspace(app: &mut App) {
        if app.can_edit_input() {
            app.input.pop();
        }
    }
}