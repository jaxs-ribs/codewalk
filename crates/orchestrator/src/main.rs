mod app;
mod backend;
mod config;
mod constants;
mod handlers;
mod relay_client;
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
    // Load .env unconditionally so RELAY_* config is available without exports
    config::load_dotenv();
    // Try to load API key; if missing, run in reduced mode (no audio/LLM)
    match config::load_api_key() {
        Ok(key) => {
            // Initialize backend with API key
            if let Err(e) = backend::initialize_backend(key).await {
                eprintln!("Warning: backend init failed: {}", e);
            }
        }
        Err(_) => {
            eprintln!("Warning: GROQ_API_KEY not set; voice and LLM disabled");
        }
    }

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
    // Connect to relay (if configured via env)
    app.init_relay().await;
    
    loop {
        app.update_blink();
        
        // Poll executor output if it's running
        if app.mode == types::Mode::ExecutorRunning {
            app.poll_executor_output().await?;
        }
        
        // Poll for new log entries
        app.poll_logs().await?;

        // Poll relay events (if connected)
        app.poll_relay().await?;
        
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
