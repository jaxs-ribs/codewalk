use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Wrap},
    Frame,
};

use crate::app::App;
use crate::types::{Mode, PendingExecutor};
use super::styles::Styles;

pub struct ConfirmationDialog;

impl ConfirmationDialog {
    pub fn render(frame: &mut Frame, app: &App) {
        if app.mode != Mode::ConfirmingExecutor || app.pending_executor.is_none() {
            return;
        }
        
        let pending = app.pending_executor.as_ref().unwrap();
        let area = Self::centered_rect(60, 40, frame.area());
        
        // Clear the area behind the dialog
        frame.render_widget(Clear, area);
        
        // Create the dialog content
        let content = Self::create_content(pending);
        
        // Create the dialog widget
        let dialog = Paragraph::new(content)
            .block(
                Block::default()
                    .title(" Confirm Executor Launch ")
                    .borders(Borders::ALL)
                    .border_style(Styles::confirmation_border())
            )
            .alignment(Alignment::Left)
            .wrap(Wrap { trim: true });
        
        frame.render_widget(dialog, area);
    }
    
    fn create_content(pending: &PendingExecutor) -> Vec<Line<'static>> {
        vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("  Executor: ", Styles::confirmation_label()),
                Span::styled(pending.executor_name.clone(), Styles::confirmation_value()),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled("  Directory: ", Styles::confirmation_label()),
                Span::styled(pending.working_dir.clone(), Styles::confirmation_value()),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled("  Prompt: ", Styles::confirmation_label()),
            ]),
            Line::from(vec![
                Span::raw("  "),
                Span::styled(pending.prompt.clone(), Styles::confirmation_prompt()),
            ]),
            Line::from(""),
            Line::from(""),
            Line::from(vec![
                Span::raw("  "),
                Span::styled("[Enter]", Styles::confirmation_key()),
                Span::raw(" Confirm   "),
                Span::styled("[Escape]", Styles::confirmation_key()),
                Span::raw(" Cancel"),
            ]),
        ]
    }
    
    /// Helper to create a centered rect
    fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
        let popup_layout = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage((100 - percent_y) / 2),
                Constraint::Percentage(percent_y),
                Constraint::Percentage((100 - percent_y) / 2),
            ])
            .split(area);

        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage((100 - percent_x) / 2),
                Constraint::Percentage(percent_x),
                Constraint::Percentage((100 - percent_x) / 2),
            ])
            .split(popup_layout[1])[1]
    }
}