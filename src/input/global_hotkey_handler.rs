use anyhow::{Result, anyhow};
use global_hotkey::{GlobalHotKeyManager, HotKeyState};
use global_hotkey::hotkey::{HotKey, Modifiers, Code};
use std::sync::mpsc;
use crate::constants::HOTKEY_TIMEOUT_MS;
use std::time::Duration;

pub struct GlobalHotkeyHandler {
    _manager: GlobalHotKeyManager,
    receiver: mpsc::Receiver<HotkeyEvent>,
}

impl GlobalHotkeyHandler {
    pub fn new() -> Result<Self> {
        let manager = GlobalHotKeyManager::new()
            .map_err(|e| anyhow!("Failed to create hotkey manager: {}", e))?;
        
        let hotkey = HotkeyBuilder::build_default()?;
        manager.register(hotkey)
            .map_err(|e| anyhow!("Failed to register hotkey: {}", e))?;
        
        let receiver = Self::create_event_receiver();
        
        Ok(Self { _manager: manager, receiver })
    }

    pub fn poll_event(&self) -> Option<HotkeyEvent> {
        self.receiver
            .recv_timeout(Duration::from_millis(HOTKEY_TIMEOUT_MS))
            .ok()
    }

    fn create_event_receiver() -> mpsc::Receiver<HotkeyEvent> {
        let (sender, receiver) = mpsc::channel();
        
        std::thread::spawn(move || {
            HotkeyListener::listen(sender);
        });
        
        receiver
    }
}

struct HotkeyBuilder;

impl HotkeyBuilder {
    fn build_default() -> Result<HotKey> {
        let modifiers = Modifiers::META | Modifiers::SHIFT;
        let code = Code::KeyR;
        
        Ok(HotKey::new(Some(modifiers), code))
    }
}

struct HotkeyListener;

impl HotkeyListener {
    fn listen(sender: mpsc::Sender<HotkeyEvent>) {
        loop {
            if let Ok(event) = global_hotkey::GlobalHotKeyEvent::receiver().recv() {
                if event.state == HotKeyState::Pressed {
                    let _ = sender.send(HotkeyEvent::ToggleRecording);
                }
            }
        }
    }
}

#[derive(Debug, Clone)]
pub enum HotkeyEvent {
    ToggleRecording,
}