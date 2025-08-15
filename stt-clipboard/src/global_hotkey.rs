use anyhow::Result;
use rdev::{listen, Event, EventType, Key};
use std::sync::mpsc::{channel, Receiver};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;

pub enum HotkeyEvent {
    ToggleRecording,
}

struct ModifierState {
    cmd: AtomicBool,
    shift: AtomicBool,
    option: AtomicBool,
}

impl ModifierState {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            cmd: AtomicBool::new(false),
            shift: AtomicBool::new(false),
            option: AtomicBool::new(false),
        })
    }
    
    fn all_pressed(&self) -> bool {
        self.cmd.load(Ordering::Relaxed) &&
        self.shift.load(Ordering::Relaxed) &&
        self.option.load(Ordering::Relaxed)
    }
}

pub fn create_global_hotkey_listener() -> Result<Receiver<HotkeyEvent>> {
    let (tx, rx) = channel();
    let modifiers = ModifierState::new();
    
    thread::spawn(move || {
        let _ = listen(move |event: Event| {
            match event.event_type {
                EventType::KeyPress(Key::MetaLeft) | EventType::KeyPress(Key::MetaRight) => {
                    modifiers.cmd.store(true, Ordering::Relaxed);
                }
                EventType::KeyRelease(Key::MetaLeft) | EventType::KeyRelease(Key::MetaRight) => {
                    modifiers.cmd.store(false, Ordering::Relaxed);
                }
                EventType::KeyPress(Key::ShiftLeft) | EventType::KeyPress(Key::ShiftRight) => {
                    modifiers.shift.store(true, Ordering::Relaxed);
                }
                EventType::KeyRelease(Key::ShiftLeft) | EventType::KeyRelease(Key::ShiftRight) => {
                    modifiers.shift.store(false, Ordering::Relaxed);
                }
                EventType::KeyPress(Key::Alt) => {
                    modifiers.option.store(true, Ordering::Relaxed);
                }
                EventType::KeyRelease(Key::Alt) => {
                    modifiers.option.store(false, Ordering::Relaxed);
                }
                EventType::KeyPress(Key::Space) => {
                    if modifiers.all_pressed() {
                        let _ = tx.send(HotkeyEvent::ToggleRecording);
                    }
                }
                _ => {}
            }
        });
    });
    
    Ok(rx)
}