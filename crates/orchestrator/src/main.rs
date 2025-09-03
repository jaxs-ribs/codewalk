mod app;
mod backend;
mod config;
mod confirmation_handler;
mod constants;
#[cfg(feature = "tui")]
mod handlers;
mod relay_client;
mod settings;
mod types;
#[cfg(feature = "tui")]
mod ui;
mod utils;
mod core_bridge;
mod log_summarizer;
mod logger;
mod session_history;

use anyhow::Result;
use app::App;

#[cfg(feature = "tui")]
use crossterm::{
    event::{self, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
#[cfg(feature = "tui")]
use ratatui::{backend::CrosstermBackend, Terminal};
#[cfg(feature = "tui")]
use std::{io, time::Duration};
#[cfg(feature = "tui")]
use handlers::InputHandler;
#[cfg(feature = "tui")]
use ui::UI;

#[cfg(feature = "tui")]
#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    logger::init_logging()?;
    // Don't log events until after TUI is setup
    // logger::log_event("STARTUP", "Orchestrator starting");
    
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

    #[cfg(feature = "tui")]
    {
        let mut terminal = setup_terminal()?;
        let result = run_application(&mut terminal).await;
        restore_terminal(&mut terminal)?;
        if let Err(e) = result {
            eprintln!("Error: {}", e);
        }
        return Ok(());
    }

    #[cfg(not(feature = "tui"))]
    unreachable!()
}

#[cfg(not(feature = "tui"))]
fn main() -> Result<()> {
    // Load .env and init backend (LLM only)
    config::load_dotenv();
    if let Ok(key) = config::load_api_key() {
        // Best-effort init; ignore errors to keep headless binary light.
        let rt = tokio::runtime::Runtime::new().expect("rt");
        let _ = rt.block_on(backend::initialize_backend(key));
    }
    // Headless stub: connect to relay and keep the process alive.
    let rt = tokio::runtime::Runtime::new().expect("rt");
    rt.block_on(async move {
        let mut app = App::new();
        app.init_relay().await;
        println!("orchestrator running without TUI (feature 'tui' disabled)");
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        }
    });
    Ok(())
}

#[cfg(feature = "tui")]
fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    Ok(Terminal::new(backend)?)
}

#[cfg(feature = "tui")]
fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

#[cfg(feature = "tui")]
async fn run_application<B: ratatui::backend::Backend>(terminal: &mut Terminal<B>) -> Result<()> {
    let mut app = App::new();
    // Connect to relay (if configured via env)
    app.init_relay().await;
    
    loop {
        #[cfg(feature = "tui-stt")]
        app.update_blink();
        
        // Poll executor output if it's running
        if app.mode == types::Mode::ExecutorRunning {
            app.poll_executor_output().await?;
        }
        
        // Poll for new log entries
        app.poll_logs().await?;

        // Poll relay events (if connected)
        app.poll_relay().await?;
        // Poll headless core outbound
        app.poll_core_outbound().await?;
        // Poll app commands (from core executor adapter)
        app.poll_app_commands().await?;
        
        terminal.draw(|frame| UI::draw(frame, &app))?;
        
        if should_quit(&mut app).await? {
            break;
        }
    }
    
    // Clean up before exit
    app.cleanup().await;
    
    Ok(())
}

#[cfg(feature = "tui")]
async fn should_quit(app: &mut App) -> Result<bool> {
    if event::poll(Duration::from_millis(constants::POLL_INTERVAL_MS))? {
        if let Event::Key(key) = event::read()? {
            return InputHandler::handle_key(app, key).await;
        }
    }
    Ok(false)
}
