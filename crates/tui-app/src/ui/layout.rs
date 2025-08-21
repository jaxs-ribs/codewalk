use ratatui::layout::{Constraint, Direction, Layout, Rect};
use crate::constants::{OVERLAY_HEIGHT_PERCENT, OVERLAY_WIDTH_PERCENT};

pub struct MainLayout {
    pub output: Rect,
    pub help: Rect,
    pub input: Rect,
}

pub struct LayoutManager;

impl LayoutManager {
    pub fn create_main_layout(area: Rect) -> MainLayout {
        let main_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Min(10),      // Output pane
                Constraint::Length(7),    // Help pane
                Constraint::Length(1),    // Input line
            ])
            .split(area);
        
        MainLayout {
            output: main_chunks[0],
            help: main_chunks[1],
            input: main_chunks[2],
        }
    }
    
    pub fn centered_rect(area: Rect) -> Rect {
        Self::centered_rect_with_size(OVERLAY_WIDTH_PERCENT, OVERLAY_HEIGHT_PERCENT, area)
    }
    
    pub fn centered_rect_with_size(width_percent: u16, height_percent: u16, area: Rect) -> Rect {
        let vertical = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage((100 - height_percent) / 2),
                Constraint::Percentage(height_percent),
                Constraint::Percentage((100 - height_percent) / 2),
            ])
            .split(area);
        
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage((100 - width_percent) / 2),
                Constraint::Percentage(width_percent),
                Constraint::Percentage((100 - width_percent) / 2),
            ])
            .split(vertical[1])[1]
    }
}