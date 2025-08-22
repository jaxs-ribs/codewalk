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
    
    pub fn highlight() -> Style {
        Style::default()
            .fg(Color::Magenta)
            .add_modifier(Modifier::BOLD)
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
    
    pub fn confirmation_border() -> Style {
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn confirmation_label() -> Style {
        Style::default()
            .fg(Color::Gray)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn confirmation_value() -> Style {
        Style::default()
            .fg(Color::White)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn confirmation_prompt() -> Style {
        Style::default()
            .fg(Color::Cyan)
    }
    
    pub fn confirmation_key() -> Style {
        Style::default()
            .fg(Color::Green)
            .add_modifier(Modifier::BOLD)
    }
}