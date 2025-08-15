mod audio;
mod groq;
mod clipboard;
mod config;
mod ui;
mod app;
mod keyboard;
mod global_hotkey;

use anyhow::Result;
use std::env;

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() > 1 && args[1] == "--global" {
        run_global().await
    } else {
        run_interactive().await
    }
}

async fn run_interactive() -> Result<()> {
    use keyboard::{KeyboardHandler, KeyAction};
    
    let api_key = config::load_api_key()?;
    
    ui::print_welcome();
    
    let keyboard = KeyboardHandler::enable_raw_mode()?;
    let mut app = app::App::new(api_key)?;
    
    loop {
        if let Some(action) = keyboard.poll_event().await? {
            match action {
                KeyAction::ToggleRecording => {
                    app.toggle_recording()?;
                    if !app.is_recording() {
                        app.process_recording().await?;
                    }
                }
                KeyAction::Quit => break,
            }
        }
    }
    
    ui::print_goodbye();
    Ok(())
}

async fn run_global() -> Result<()> {
    println!("\n🎤 STT-Clipboard (Global Mode)");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Press Cmd+Shift+Option+Space to toggle recording");
    println!("Works from anywhere on your Mac!");
    println!("Press Ctrl+C to quit\n");
    
    let api_key = config::load_api_key()?;
    let mut app = app::App::new(api_key)?;
    
    // Set up Ctrl+C handler
    let running = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));
    let r = running.clone();
    
    ctrlc::set_handler(move || {
        r.store(false, std::sync::atomic::Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");
    
    // Create global hotkey listener
    let hotkey_rx = global_hotkey::create_global_hotkey_listener()?;
    
    println!("Listening for global hotkey...\n");
    
    // Listen for hotkey events
    while running.load(std::sync::atomic::Ordering::SeqCst) {
        // Check for hotkey events with timeout
        match hotkey_rx.recv_timeout(std::time::Duration::from_millis(100)) {
            Ok(global_hotkey::HotkeyEvent::ToggleRecording) => {
                app.toggle_recording()?;
                if app.is_recording() {
                    println!("🔴 Recording started...");
                } else {
                    println!("⏹️  Recording stopped, processing...");
                    app.process_recording().await?;
                }
            }
            Err(_) => {
                // Timeout - continue loop
            }
        }
    }
    
    println!("\nGoodbye!");
    Ok(())
}