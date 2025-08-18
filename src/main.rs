mod constants;
mod interfaces;
mod audio;
mod services;
mod ui;
mod application;
mod input;

use anyhow::Result;
use application::ApplicationFactory;
use input::RdevHotkeyHandler;
use ui::WelcomeScreen;
use std::time::Duration;
use std::thread;

#[tokio::main]
async fn main() -> Result<()> {
    WelcomeScreen::display();
    
    let hotkey_handler = RdevHotkeyHandler::new()?;
    let mut session = ApplicationFactory::create_recording_session()?;
    
    println!("\n⌨️  Test hotkey: Press 'T' key");
    println!("   (We'll add modifiers once basic key detection works)");
    println!("   • Press T to start recording");
    println!("   • Press T again to stop and copy to clipboard");
    
    println!("🎧 Listening for hotkeys... (Press Ctrl+C to quit)\n");
    
    loop {
        if hotkey_handler.check_pressed() {
            println!("🎯 Hotkey triggered!");
            session.toggle_recording()?;
            if !session.is_recording() {
                session.process_recording().await?;
            }
        }
        
        // Small delay to prevent busy waiting
        thread::sleep(Duration::from_millis(10));
    }
}