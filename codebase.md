# .claude/settings.local.json

```json
{
  "permissions": {
    "allow": [
      "Bash(unzip:*)",
      "Bash(rm:*)",
      "Bash(wget:*)",
      "Bash(cargo init:*)",
      "Bash(cargo:*)"
    ],
    "additionalDirectories": [
      "/Users/fresh"
    ]
  }
}
```

# .gitignore

```
/target

```

# Cargo.toml

```toml
[package]
name = "tui-poc"
version = "0.1.0"
edition = "2024"

[dependencies]
ratatui = "0.28"
crossterm = "0.28"
anyhow = "1.0"
tracing = "0.1"
tracing-subscriber = "0.3"
serde_json = "1.0"

```

# src/app.rs

```rs
use anyhow::Result;
use std::time::Duration;

use crate::backend::{self, PlanInfo};
use crate::constants::{self, messages, prefixes};
use crate::types::{Mode, PlanState, RecordingState};

pub struct App {
    pub output: Vec<String>,
    pub input: String,
    pub mode: Mode,
    pub plan: PlanState,
    pub recording: RecordingState,
}

impl App {
    pub fn new() -> Self {
        Self {
            output: Vec::new(),
            input: String::new(),
            mode: Mode::Idle,
            plan: PlanState::new(),
            recording: RecordingState::new(),
        }
    }

    pub fn append_output(&mut self, line: String) {
        self.output.push(line);
        self.trim_output();
    }

    fn trim_output(&mut self) {
        if self.output.len() > constants::MAX_OUTPUT_LINES {
            self.output.remove(0);
        }
    }

    pub fn start_recording(&mut self) -> Result<()> {
        self.mode = Mode::Recording;
        self.recording.start();
        backend::record_voice(true)?;
        Ok(())
    }

    pub fn stop_recording(&mut self) -> Result<()> {
        backend::record_voice(false)?;
        let audio = backend::take_recorded_audio()?;
        
        if audio.is_empty() {
            self.handle_empty_recording();
        } else {
            self.process_audio(audio)?;
        }
        
        self.recording.stop();
        Ok(())
    }

    fn handle_empty_recording(&mut self) {
        self.append_output(format!("{} {}", prefixes::ASR, messages::NO_AUDIO));
        self.mode = Mode::Idle;
    }

    fn process_audio(&mut self, audio: Vec<u8>) -> Result<()> {
        let utterance = backend::voice_to_text(audio)?;
        self.append_output(format!("{} {}", prefixes::ASR, utterance));
        self.create_plan(&utterance)?;
        Ok(())
    }

    pub fn create_plan(&mut self, text: &str) -> Result<()> {
        let plan_json = backend::text_to_llm_cmd(text)?;
        let plan_info = backend::parse_plan_json(&plan_json).ok();
        
        if let Some(info) = plan_info {
            self.handle_plan_response(info, plan_json)?;
        } else {
            self.handle_invalid_plan();
        }
        
        Ok(())
    }

    fn handle_plan_response(&mut self, info: PlanInfo, json: String) -> Result<()> {
        match info.status.as_str() {
            "ok" if info.has_steps => {
                let cmd = backend::extract_cmd(&json)?;
                self.plan.set(json.clone(), cmd);
                self.mode = Mode::PlanPending;
                self.append_output(format!("{} {}", prefixes::PLAN, json));
            }
            "deny" => {
                let reason = info.reason.unwrap_or_else(|| "unknown".to_string());
                self.append_output(format!("{} {}{}", prefixes::PLAN, messages::PLAN_DENY_PREFIX, reason));
                self.mode = Mode::Idle;
            }
            _ => self.handle_invalid_plan(),
        }
        Ok(())
    }

    fn handle_invalid_plan(&mut self) {
        self.append_output(format!("{} {}", prefixes::PLAN, messages::PLAN_INVALID));
        self.mode = Mode::Idle;
    }

    pub fn execute_plan(&mut self) {
        if let Some(cmd) = &self.plan.command.clone() {
            self.mode = Mode::Executing;
            self.append_output(format!("{} {}", prefixes::EXEC, cmd));
            self.simulate_execution();
            self.complete_execution();
        }
    }

    fn simulate_execution(&mut self) {
        self.append_output(messages::SIMULATED_OUTPUT.to_string());
        self.append_output(messages::DONE.to_string());
    }

    fn complete_execution(&mut self) {
        self.plan.clear();
        self.mode = Mode::Idle;
    }

    pub fn cancel_current_operation(&mut self) {
        match self.mode {
            Mode::PlanPending => {
                self.append_output(format!("{} {}", prefixes::PLAN, messages::PLAN_CANCELED));
                self.plan.clear();
                self.mode = Mode::Idle;
            }
            Mode::Recording => {
                self.recording.stop();
                self.mode = Mode::Idle;
            }
            _ => {}
        }
    }

    pub fn handle_text_input(&mut self) -> Result<()> {
        if !self.input.is_empty() {
            let text = self.input.clone();
            self.append_output(format!("{} {}", prefixes::UTTERANCE, text));
            self.input.clear();
            self.create_plan(&text)?;
        }
        Ok(())
    }

    pub fn update_blink(&mut self) {
        if self.recording.last_blink.elapsed() > Duration::from_millis(constants::BLINK_INTERVAL_MS) {
            self.recording.blink_state = !self.recording.blink_state;
            self.recording.last_blink = std::time::Instant::now();
        }
    }

    pub fn get_recording_time(&self) -> String {
        let elapsed = self.recording.elapsed_seconds();
        format!("{:02}:{:02}", elapsed / 60, elapsed % 60)
    }

    pub fn can_edit_input(&self) -> bool {
        self.mode == Mode::Idle
    }

    pub fn can_start_recording(&self) -> bool {
        self.mode == Mode::Idle && !self.recording.is_active
    }

    pub fn can_stop_recording(&self) -> bool {
        self.mode == Mode::Recording && self.recording.is_active
    }

    pub fn can_cancel(&self) -> bool {
        matches!(self.mode, Mode::Recording | Mode::PlanPending)
    }
}
```

# src/backend.rs

```rs
use anyhow::Result;
use serde_json::Value;

pub fn record_voice(_start: bool) -> Result<()> {
    Ok(())
}

pub fn take_recorded_audio() -> Result<Vec<u8>> {
    Ok(vec![1, 2, 3])
}

pub fn voice_to_text(_audio: Vec<u8>) -> Result<String> {
    Ok("connect to bandit level zero and read readme".to_string())
}

pub fn text_to_llm_cmd(text: &str) -> Result<String> {
    if text.contains("bandit") {
        Ok(r#"{"status":"ok","confidence":{"score":0.8,"label":"high"},"plan":{"cwd":"~","explanation":"SSH then print README","steps":[{"cmd":"ssh bandit0@bandit.labs.overthewire.org -p 2220"},{"cmd":"cat readme"}]}}"#.to_string())
    } else {
        Ok(format!(
            r#"{{"status":"ok","plan":{{"steps":[{{"cmd":"echo 'Simulated command for: {}'"}}]}}}}"#,
            text
        ))
    }
}

pub fn extract_cmd(plan_json: &str) -> Result<String> {
    let json: Value = serde_json::from_str(plan_json)?;
    
    json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .and_then(|steps| steps.first())
        .and_then(|step| step.get("cmd"))
        .and_then(|c| c.as_str())
        .map(String::from)
        .ok_or_else(|| anyhow::anyhow!("Could not extract command from plan"))
}

pub fn parse_plan_json(json_str: &str) -> Result<PlanInfo> {
    let json: Value = serde_json::from_str(json_str)?;
    
    let status = json.get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("");
    
    let reason = json.get("reason")
        .and_then(|r| r.as_str())
        .map(String::from);
    
    let has_steps = json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .is_some();
    
    let explanation = json.get("plan")
        .and_then(|p| p.get("explanation"))
        .and_then(|e| e.as_str())
        .map(String::from);
    
    let step_count = json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .map(|steps| steps.len())
        .unwrap_or(0);
    
    Ok(PlanInfo {
        status: status.to_string(),
        reason,
        has_steps,
        explanation,
        step_count,
    })
}

pub struct PlanInfo {
    pub status: String,
    pub reason: Option<String>,
    pub has_steps: bool,
    #[allow(dead_code)]
    pub explanation: Option<String>,
    #[allow(dead_code)]
    pub step_count: usize,
}
```

# src/constants.rs

```rs
pub const MAX_OUTPUT_LINES: usize = 1000;
pub const BLINK_INTERVAL_MS: u64 = 500;
pub const POLL_INTERVAL_MS: u64 = 50;
pub const OVERLAY_WIDTH_PERCENT: u16 = 60;
pub const OVERLAY_HEIGHT_PERCENT: u16 = 40;

pub mod prefixes {
    pub const ASR: &str = "ASR>";
    pub const PLAN: &str = "PLAN>";
    pub const EXEC: &str = "EXEC>";
    pub const WARN: &str = "WARN>";
    pub const UTTERANCE: &str = "UTTERANCE>";
}

pub mod messages {
    pub const NO_AUDIO: &str = "no audio captured";
    pub const PLAN_CANCELED: &str = "canceled";
    pub const PLAN_INVALID: &str = "invalid plan";
    pub const PLAN_DENY_PREFIX: &str = "deny: ";
    pub const DONE: &str = "DONE";
    pub const SIMULATED_OUTPUT: &str = "[simulated command output]";
}
```

# src/handlers.rs

```rs
use anyhow::Result;
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

use crate::app::App;
use crate::types::Mode;

pub struct InputHandler;

impl InputHandler {
    pub fn handle_key(app: &mut App, key: KeyEvent) -> Result<bool> {
        if !Self::is_valid_event(key) {
            return Ok(false);
        }

        // Check for Ctrl+C to quit
        if key.code == KeyCode::Char('c') && key.modifiers == KeyModifiers::CONTROL {
            return Ok(true); // Quit signal
        }

        Self::process_key(app, key)?;
        Ok(false)
    }

    fn is_valid_event(key: KeyEvent) -> bool {
        matches!(key.kind, KeyEventKind::Press)
    }

    fn process_key(app: &mut App, key: KeyEvent) -> Result<()> {
        if key.kind == KeyEventKind::Press {
            Self::handle_key_press(app, key)?;
        }
        Ok(())
    }

    fn handle_key_press(app: &mut App, key: KeyEvent) -> Result<()> {
        match (key.code, key.modifiers) {
            (KeyCode::Char('r'), KeyModifiers::CONTROL) => Self::handle_record_toggle(app)?,
            (KeyCode::Enter, _) => Self::handle_enter(app)?,
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

    fn handle_record_toggle(app: &mut App) -> Result<()> {
        if app.can_start_recording() {
            app.start_recording()?;
        } else if app.can_stop_recording() {
            app.stop_recording()?;
        }
        Ok(())
    }

    fn handle_enter(app: &mut App) -> Result<()> {
        match app.mode {
            Mode::Idle => app.handle_text_input()?,
            Mode::PlanPending => app.execute_plan(),
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
```

# src/main.rs

```rs
mod app;
mod backend;
mod constants;
mod handlers;
mod types;
mod ui;

use anyhow::Result;
use crossterm::{
    event::{self, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::{io, time::Duration};

use app::App;
use handlers::InputHandler;
use ui::UI;

fn main() -> Result<()> {
    let mut terminal = setup_terminal()?;
    let result = run_application(&mut terminal);
    restore_terminal(&mut terminal)?;
    
    if let Err(e) = result {
        eprintln!("Error: {}", e);
    }
    
    Ok(())
}

fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    Ok(Terminal::new(backend)?)
}

fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

fn run_application<B: ratatui::backend::Backend>(terminal: &mut Terminal<B>) -> Result<()> {
    let mut app = App::new();
    
    loop {
        app.update_blink();
        terminal.draw(|frame| UI::draw(frame, &app))?;
        
        if should_quit(&mut app)? {
            break;
        }
    }
    
    Ok(())
}

fn should_quit(app: &mut App) -> Result<bool> {
    if event::poll(Duration::from_millis(constants::POLL_INTERVAL_MS))? {
        if let Event::Key(key) = event::read()? {
            return InputHandler::handle_key(app, key);
        }
    }
    Ok(false)
}
```

# src/types.rs

```rs
use std::time::Instant;

#[derive(Debug, Clone, PartialEq)]
pub enum Mode {
    Idle,
    Recording,
    PlanPending,
    Executing,
}

pub struct RecordingState {
    pub is_active: bool,
    pub started_at: Option<Instant>,
    pub blink_state: bool,
    pub last_blink: Instant,
}

impl RecordingState {
    pub fn new() -> Self {
        Self {
            is_active: false,
            started_at: None,
            blink_state: false,
            last_blink: Instant::now(),
        }
    }

    pub fn start(&mut self) {
        self.is_active = true;
        self.started_at = Some(Instant::now());
    }

    pub fn stop(&mut self) {
        self.is_active = false;
        self.started_at = None;
    }

    pub fn elapsed_seconds(&self) -> u64 {
        self.started_at
            .map(|start| start.elapsed().as_secs())
            .unwrap_or(0)
    }
}

pub struct PlanState {
    pub json: Option<String>,
    pub command: Option<String>,
}

impl PlanState {
    pub fn new() -> Self {
        Self {
            json: None,
            command: None,
        }
    }

    pub fn set(&mut self, json: String, command: String) {
        self.json = Some(json);
        self.command = Some(command);
    }

    pub fn clear(&mut self) {
        self.json = None;
        self.command = None;
    }

    pub fn is_pending(&self) -> bool {
        self.json.is_some()
    }
}
```

# src/ui/components.rs

```rs
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
        
        let widget = if app.mode == Mode::PlanPending {
            list.style(Styles::dimmed())
        } else {
            list
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
            Self::help_line("Ctrl+R", "Toggle voice recording (start/finalize)"),
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
```

# src/ui/layout.rs

```rs
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
```

# src/ui/mod.rs

```rs
mod components;
mod layout;
mod styles;

use ratatui::Frame;

use crate::app::App;
use components::{HelpPane, InputLine, OutputPane, PlanOverlay};
use layout::LayoutManager;

pub struct UI;

impl UI {
    pub fn draw(frame: &mut Frame, app: &App) {
        let chunks = LayoutManager::create_main_layout(frame.area());
        
        OutputPane::render(frame, &chunks.output, app);
        HelpPane::render(frame, &chunks.help, app);
        InputLine::render(frame, &chunks.input, app);
        
        if app.plan.is_pending() {
            PlanOverlay::render(frame, app);
        }
        
        Self::set_cursor(frame, app, &chunks.input);
    }
    
    fn set_cursor(frame: &mut Frame, app: &App, input_area: &ratatui::layout::Rect) {
        if app.can_edit_input() {
            let cursor_x = (2 + app.input.len()) as u16;
            let cursor_y = input_area.y;
            
            if cursor_x < input_area.x + input_area.width {
                frame.set_cursor_position((input_area.x + cursor_x, cursor_y));
            }
        }
    }
}
```

# src/ui/styles.rs

```rs
use ratatui::style::{Color, Modifier, Style};
use crate::constants::prefixes;

pub struct Styles;

impl Styles {
    pub fn default() -> Style {
        Style::default().fg(Color::White)
    }
    
    pub fn dimmed() -> Style {
        Style::default().fg(Color::DarkGray)
    }
    
    pub fn mode_indicator() -> Style {
        Style::default().fg(Color::Gray)
    }
    
    pub fn recording_indicator() -> Style {
        Style::default()
            .fg(Color::Red)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn overlay_border() -> Style {
        Style::default().fg(Color::Yellow)
    }
    
    pub fn overlay_footer() -> Style {
        Style::default().fg(Color::Gray)
    }
    
    pub fn help_key() -> Style {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn help_desc() -> Style {
        Style::default().fg(Color::Gray)
    }
    
    pub fn help_title() -> Style {
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn for_output_line(line: &str) -> Style {
        if line.starts_with(prefixes::ASR) {
            Style::default().fg(Color::Cyan)
        } else if line.starts_with(prefixes::PLAN) {
            Style::default().fg(Color::Yellow)
        } else if line.starts_with(prefixes::EXEC) {
            Style::default().fg(Color::Green)
        } else if line.starts_with(prefixes::WARN) {
            Style::default().fg(Color::Red)
        } else if line.starts_with(prefixes::UTTERANCE) {
            Style::default().fg(Color::Blue)
        } else {
            Self::default()
        }
    }
}
```

