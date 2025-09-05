use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Wrap},
    Frame,
};

use crate::app::App;
use crate::types::Mode;
use crate::utils::TextWrapper;
use super::styles::Styles;

pub struct ErrorDialog;

impl ErrorDialog {
    pub fn render(frame: &mut Frame, app: &App) {
        if app.mode != Mode::ShowingError || app.error_info.is_none() {
            return;
        }
        
        let error = app.error_info.as_ref().unwrap();
        let area = Self::centered_rect(70, 50, frame.area());
        
        // Clear the area behind the dialog
        frame.render_widget(Clear, area);
        
        // Create the dialog content
        let content = Self::create_content(error);
        
        // Create the dialog widget with error styling
        let dialog = Paragraph::new(content)
            .block(
                Block::default()
                    .title(format!(" {} ", error.title))
                    .borders(Borders::ALL)
                    .border_style(Styles::error_border())
            )
            .alignment(Alignment::Left)
            .wrap(Wrap { trim: true })
            .style(Styles::error_text());
        
        frame.render_widget(dialog, area);
    }
    
    fn create_content(error: &crate::types::ErrorInfo) -> Vec<Line<'static>> {
        let mut lines = vec![Line::from("")];
        
        // Wrap the main error message
        let wrapped_message = TextWrapper::wrap_line(&error.message);
        for (i, msg_line) in wrapped_message.into_iter().enumerate() {
            if i == 0 {
                lines.push(Line::from(vec![
                    Span::styled("  ", Styles::default()),
                    Span::styled(msg_line, Styles::error_message()),
                ]));
            } else {
                lines.push(Line::from(vec![
                    Span::styled("    ", Styles::default()),
                    Span::styled(msg_line, Styles::error_message()),
                ]));
            }
        }
        
        lines.push(Line::from(""));
        
        if let Some(details) = &error.details {
            lines.push(Line::from(vec![
                Span::styled("  Details: ", Styles::error_label()),
            ]));
            
            // Split details by newlines and wrap each line
            for detail_line in details.lines() {
                let wrapped_detail = TextWrapper::wrap_line(detail_line);
                for wrapped in wrapped_detail {
                    lines.push(Line::from(vec![
                        Span::raw("    "),
                        Span::styled(wrapped, Styles::error_details()),
                    ]));
                }
            }
            
            lines.push(Line::from(""));
        }
        
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled("[Enter/Escape]", Styles::error_key()),
            Span::raw(" Dismiss"),
        ]));
        
        lines
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