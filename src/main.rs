mod app;
mod audio;
mod backend;
mod config;
mod constants;
mod groq;
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

#[tokio::main]
async fn main() -> Result<()> {
    // Load API key
    let api_key = match config::load_api_key() {
        Ok(key) => key,
        Err(e) => {
            eprintln!("Error loading API key: {}", e);
            eprintln!("Please set GROQ_API_KEY environment variable or add it to .env file");
            return Ok(());
        }
    };

    // Initialize backend with API key
    backend::initialize_backend(api_key).await?;

    let mut terminal = setup_terminal()?;
    let result = run_application(&mut terminal).await;
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

async fn run_application<B: ratatui::backend::Backend>(terminal: &mut Terminal<B>) -> Result<()> {
    let mut app = App::new();
    
    loop {
        app.update_blink();
        terminal.draw(|frame| UI::draw(frame, &app))?;
        
        if should_quit(&mut app).await? {
            break;
        }
    }
    
    Ok(())
}

async fn should_quit(app: &mut App) -> Result<bool> {
    if event::poll(Duration::from_millis(constants::POLL_INTERVAL_MS))? {
        if let Event::Key(key) = event::read()? {
            return InputHandler::handle_key(app, key).await;
        }
    }
    Ok(false)
}