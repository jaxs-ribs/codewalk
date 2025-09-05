use ratatui::{
    layout::Rect,
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

use crate::app::App;
use control_center::{ParsedLogLine, LogType};
use super::styles::Styles;

pub struct LogPane;

impl LogPane {
    pub fn render(frame: &mut Frame, area: &Rect, app: &App) {
        let height = area.height.saturating_sub(2) as usize; // Account for borders
        let items = Self::create_log_items(app, height);
        let list = Self::create_list(items, app);
        
        frame.render_widget(list, *area);
    }
    
    fn create_log_items(app: &App, height: usize) -> Vec<ListItem<'_>> {
        // Calculate visible range based on scroll state for logs
        let total_logs = app.session_logs.len();
        
        let start_idx = if total_logs > height {
            if app.log_scroll.auto_scroll {
                total_logs.saturating_sub(height)
            } else {
                std::cmp::min(app.log_scroll.offset, total_logs.saturating_sub(height))
            }
        } else {
            0
        };
        
        let end_idx = std::cmp::min(start_idx + height, total_logs);
        
        app.session_logs[start_idx..end_idx]
            .iter()
            .map(|log| Self::format_log_item(log))
            .collect()
    }
    
    fn format_log_item(log: &ParsedLogLine) -> ListItem<'static> {
        let style = Self::get_log_style(&log.entry_type);
        let prefix = Self::get_log_prefix(&log.entry_type);
        
        // Increased width for better readability
        const MAX_WIDTH: usize = 60;
        let prefix_len = prefix.len() + 1; // +1 for space
        let content_max = MAX_WIDTH.saturating_sub(prefix_len);
        
        // Clean up content - remove newlines and extra spaces
        let clean_content = log.content
            .replace('\n', " ")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        
        // Smart truncation based on content type
        let display_content = if clean_content.len() > content_max {
            // For file paths, show end rather than beginning
            if clean_content.contains('/') || clean_content.contains('\\') {
                if clean_content.len() > content_max {
                    format!("...{}", &clean_content[clean_content.len().saturating_sub(content_max - 3)..])
                } else {
                    clean_content
                }
            } else {
                // For regular text, try to find a good break point
                let mut break_point = content_max.saturating_sub(3); // Account for "..."
                if let Some(space_pos) = clean_content[..content_max.min(clean_content.len())].rfind(' ') {
                    if space_pos > content_max / 2 {
                        break_point = space_pos;
                    }
                }
                format!("{}...", &clean_content[..break_point.min(clean_content.len())])
            }
        } else {
            clean_content
        };
        
        let text = format!("{} {}", prefix, display_content);
        ListItem::new(Line::from(vec![
            Span::styled(text, style)
        ]))
    }
    
    fn get_log_prefix(log_type: &LogType) -> &'static str {
        match log_type {
            LogType::UserMessage => "[USER]",
            LogType::AssistantMessage => "[ASST]",
            LogType::ToolCall => "[TOOL]",
            LogType::ToolResult => "[RSLT]",
            LogType::Status => "[STAT]",
            LogType::Error => "[ERR!]",
            LogType::Unknown => "[????]",
        }
    }
    
    fn get_log_style(log_type: &LogType) -> ratatui::style::Style {
        use ratatui::style::{Color, Style};
        
        match log_type {
            LogType::UserMessage => Style::default().fg(Color::Blue),
            LogType::AssistantMessage => Style::default().fg(Color::Green),
            LogType::ToolCall => Style::default().fg(Color::Yellow),
            LogType::ToolResult => Style::default().fg(Color::Cyan),
            LogType::Status => Style::default().fg(Color::Gray),
            LogType::Error => Style::default().fg(Color::Red),
            LogType::Unknown => Style::default().fg(Color::DarkGray),
        }
    }
    
    fn create_list<'a>(items: Vec<ListItem<'a>>, app: &App) -> List<'a> {
        let mut block = Block::default()
            .title(" Session Logs ")
            .borders(Borders::ALL)
            .border_style(Styles::default());
        
        // Add scroll indicator if not auto-scrolling
        if !app.log_scroll.auto_scroll {
            let total = app.session_logs.len();
            let position = app.log_scroll.offset + 1;
            let indicator = format!(" Session Logs [{}/{}] ", 
                                  std::cmp::min(position, total), total);
            block = block.title(indicator);
        }
        
        List::new(items)
            .block(block)
            .style(Styles::default())
    }
}
