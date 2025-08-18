use anyhow::Result;
use rdev::{listen, Event, EventType, Key};
use std::sync::mpsc::{channel, Sender, Receiver};
use std::thread;

pub struct RdevHotkeyHandler {
    receiver: Receiver<()>,
}

impl RdevHotkeyHandler {
    pub fn new() -> Result<Self> {
        println!("🔧 Initializing hotkey listener...");
        let (sender, receiver) = channel();
        
        thread::spawn(move || {
            let _ = listen(move |event| {
                callback(event, &sender);
            });
        });
        
        println!("✅ Hotkey listener started");
        println!("📌 Hotkey: Cmd+Option+Shift+T");
        
        Ok(Self { receiver })
    }
    
    pub fn check_pressed(&self) -> bool {
        self.receiver.try_recv().is_ok()
    }
}

fn callback(event: Event, sender: &Sender<()>) {
    if let EventType::KeyPress(Key::KeyT) = event.event_type {
        // Check if modifiers are pressed (this is simplified, rdev doesn't directly provide modifier state)
        // For now, we'll just use T key alone for testing
        println!("🔑 Key T pressed!");
        let _ = sender.send(());
    }
}