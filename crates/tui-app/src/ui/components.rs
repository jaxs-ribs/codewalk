use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap},
    Frame,
};
use serde_json::Value;

use crate::app::App;
use crate::types::Mode;
use super::layout::LayoutManager;
use super::styles::Styles;

pub struct OutputPane;

impl OutputPane {
    pub fn render(frame: &mut Frame, area: &Rect, app: &App) {
        let items = Self::create_list_items(app);
        let list = Self::create_list(items);
        
        let widget = match app.mode {
            Mode::PlanPending => list.style(Styles::dimmed()),
            Mode::ClaudeRunning => list.style(Styles::highlight()),
            _ => list
        };
        
        frame.render_widget(widget, *area);
    }
    
    fn create_list_items(app: &App) -> Vec<ListItem<'_>> {
        app.output
            .iter()
            .map(|line| {
                let style = Styles::for_output_line(line);
                ListItem::new(Line::from(line.as_str())).style(style)
            })
            .collect()
    }
    
    fn create_list(items: Vec<ListItem>) -> List {
        List::new(items)
            .block(Block::default().borders(Borders::NONE))
            .style(Styles::default())
    }
}

pub struct HelpPane;

impl HelpPane {
    pub fn render(frame: &mut Frame, area: &Rect, _app: &App) {
        let help_text = Self::create_help_content();
        
        let widget = Paragraph::new(help_text)
            .block(
                Block::default()
                    .title(" Shortcuts ")
                    .borders(Borders::ALL)
                    .style(Styles::help_title())
            )
            .wrap(Wrap { trim: true });
        
        frame.render_widget(widget, *area);
    }
    
    fn create_help_content() -> Vec<Line<'static>> {
        vec![
            Self::help_line("Ctrl+R", "🎤 Toggle voice recording (uses Groq Whisper)"),
            Self::help_line("Enter", "Submit text / Confirm plan"),
            Self::help_line("Esc", "Cancel recording or plan"),
            Self::help_line("n", "Cancel plan (when pending)"),
            Self::help_line("Ctrl+C", "Quit application"),
        ]
    }
    
    fn help_line(key: &'static str, desc: &'static str) -> Line<'static> {
        Line::from(vec![
            Span::styled(format!("{:<10}", key), Styles::help_key()),
            Span::styled(desc, Styles::help_desc()),
        ])
    }
}

pub struct InputLine;

impl InputLine {
    pub fn render(frame: &mut Frame, area: &Rect, app: &App) {
        let spans = Self::create_status_spans(app, area.width as usize);
        let line = Line::from(spans);
        
        let widget = Paragraph::new(line)
            .style(Styles::default())
            .alignment(Alignment::Left);
        
        frame.render_widget(widget, *area);
    }
    
    fn create_status_spans(app: &App, width: usize) -> Vec<Span<'_>> {
        let mut spans = vec![Span::raw(format!("> {}", app.input))];
        
        let input_len = 2 + app.input.len();
        let mode_text = Self::get_mode_text(&app.mode);
        let mode_display = format!("[mode: {}]", mode_text);
        let mode_len = mode_display.len();
        
        let (rec_indicator, rec_len) = Self::get_recording_indicator(app);
        
        let total_right_len = mode_len + rec_len;
        let spacing_needed = width.saturating_sub(input_len + total_right_len);
        
        spans.push(Span::raw(" ".repeat(spacing_needed)));
        spans.push(Span::styled(mode_display, Styles::mode_indicator()));
        
        if !rec_indicator.is_empty() {
            spans.push(Span::styled(rec_indicator, Styles::recording_indicator()));
        }
        
        spans
    }
    
    fn get_mode_text(mode: &Mode) -> &'static str {
        match mode {
            Mode::Idle => "Idle",
            Mode::Recording => "Recording",
            Mode::PlanPending => "PlanPending",
            Mode::Executing => "Executing",
            Mode::ClaudeRunning => "Claude Running",
        }
    }
    
    fn get_recording_indicator(app: &App) -> (String, usize) {
        if app.mode == Mode::Recording {
            let dot = if app.recording.blink_state { "●" } else { "○" };
            let indicator = format!("  [REC {} {}]", dot, app.get_recording_time());
            let len = indicator.len();
            (indicator, len)
        } else {
            (String::new(), 0)
        }
    }
}

pub struct PlanOverlay;

impl PlanOverlay {
    pub fn render(frame: &mut Frame, app: &App) {
        let area = LayoutManager::centered_rect(frame.area());
        
        frame.render_widget(Clear, area);
        
        let block = Self::create_border();
        let inner = block.inner(area);
        frame.render_widget(block, area);
        
        let chunks = Self::create_layout(inner);
        
        Self::render_content(frame, &chunks[1], app);
        Self::render_footer(frame, &chunks[2]);
    }
    
    fn create_border() -> Block<'static> {
        Block::default()
            .title(" Plan Pending ")
            .borders(Borders::ALL)
            .style(Styles::overlay_border())
    }
    
    fn create_layout(area: Rect) -> Vec<Rect> {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1),
                Constraint::Min(3),
                Constraint::Length(2),
            ])
            .split(area)
            .to_vec()
    }
    
    fn render_content(frame: &mut Frame, area: &Rect, app: &App) {
        let content = Self::build_content(app);
        
        let widget = Paragraph::new(content)
            .wrap(Wrap { trim: true })
            .style(Styles::default());
        
        frame.render_widget(widget, *area);
    }
    
    fn build_content(app: &App) -> String {
        let mut content = String::new();
        
        if let Some(cmd) = &app.plan.command {
            let display_cmd = Self::truncate_command(cmd, 50);
            content.push_str(&format!("Command: {}\n", display_cmd));
        }
        
        if let Some(json) = &app.plan.json {
            Self::append_plan_details(&mut content, json);
        }
        
        content
    }
    
    fn truncate_command(cmd: &str, max_len: usize) -> String {
        if cmd.len() > max_len {
            format!("{}...", &cmd[..max_len - 3])
        } else {
            cmd.to_string()
        }
    }
    
    fn append_plan_details(content: &mut String, json: &str) {
        if let Ok(parsed) = serde_json::from_str::<Value>(json) {
            if let Some(steps) = parsed.get("plan")
                .and_then(|p| p.get("steps"))
                .and_then(|s| s.as_array())
            {
                if steps.len() > 1 {
                    content.push_str(&format!("\n{} total steps", steps.len()));
                }
            }
            
            if let Some(explanation) = parsed.get("plan")
                .and_then(|p| p.get("explanation"))
                .and_then(|e| e.as_str())
            {
                content.push_str(&format!("\n{}", explanation));
            }
        }
    }
    
    fn render_footer(frame: &mut Frame, area: &Rect) {
        let widget = Paragraph::new("[Enter] Confirm    [Esc] Cancel")
            .alignment(Alignment::Center)
            .style(Styles::overlay_footer());
        
        frame.render_widget(widget, *area);
    }
}