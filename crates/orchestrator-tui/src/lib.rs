pub mod state;
pub mod types;
pub mod constants;
pub mod utils;
pub mod app;
pub mod log_types;

// Gate unfinished UI modules behind an optional `ui` feature.
// This keeps the crate buildable while UI extraction is in progress.
#[cfg(feature = "ui")]
pub mod ui;
#[cfg(feature = "ui")]
pub mod handlers;

pub use state::{TuiState, Tab, ScrollState, ErrorDisplay};

use ratatui::backend::Backend;
use ratatui::Terminal;
use anyhow::Result;

/// Main UI drawing function
pub fn draw_ui<B: Backend>(
    terminal: &mut Terminal<B>,
    _state: &TuiState,
) -> Result<()> {
    terminal.draw(|f| {
        // The UI drawing logic will be moved here from the main app
        // For now, just a placeholder
        use ratatui::widgets::{Block, Borders};
        use ratatui::layout::{Layout, Direction, Constraint};
        
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Min(1),
                Constraint::Length(3),
            ])
            .split(f.area());
        
        let output_block = Block::default()
            .borders(Borders::ALL)
            .title("Output");
        f.render_widget(output_block, chunks[0]);
        
        let input_block = Block::default()
            .borders(Borders::ALL)
            .title("Input");
        f.render_widget(input_block, chunks[1]);
    })?;
    
    Ok(())
}
