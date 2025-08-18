mod constants;
mod interfaces;
mod audio;
mod services;
mod ui;
mod application;
mod input;

use anyhow::Result;
use application::ApplicationFactory;
use input::{GlobalHotkeyHandler, HotkeyEvent};
use ui::WelcomeScreen;

#[tokio::main]
async fn main() -> Result<()> {
    WelcomeScreen::display();
    
    let hotkey_handler = GlobalHotkeyHandler::new()?;
    let mut session = ApplicationFactory::create_recording_session()?;
    
    println!("\n⌨️  Global hotkey: Cmd+Shift+R");
    println!("   Works from any application!");
    println!("   • Press once to start recording");
    println!("   • Press again to stop and copy to clipboard\n");
    
    loop {
        if let Some(HotkeyEvent::ToggleRecording) = hotkey_handler.poll_event() {
            session.toggle_recording()?;
            if !session.is_recording() {
                session.process_recording().await?;
            }
        }
    }
}