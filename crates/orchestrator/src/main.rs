mod app;
mod backend;
mod config;
mod constants;
mod handlers;
mod settings;
mod types;
mod ui;
mod utils;

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
        Err(_) => {
            eprintln!("Error: GROQ_API_KEY environment variable not set");
            eprintln!("Please run: export GROQ_API_KEY=your_key_here");
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
        
        // Poll executor output if it's running
        if app.mode == types::Mode::ExecutorRunning {
            app.poll_executor_output().await?;
        }
        
        // Poll for new log entries
        app.poll_logs().await?;
        
        terminal.draw(|frame| UI::draw(frame, &app))?;
        
        if should_quit(&mut app).await? {
            break;
        }
    }
    
    // Clean up before exit
    app.cleanup().await;
    
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
