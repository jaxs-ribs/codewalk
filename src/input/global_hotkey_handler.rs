use anyhow::{Result, anyhow};
use global_hotkey::{GlobalHotKeyManager, HotKeyState};
use global_hotkey::hotkey::{HotKey, Code, Modifiers};

pub struct GlobalHotkeyHandler {
    _manager: GlobalHotKeyManager,
    hotkey: HotKey,
}

impl GlobalHotkeyHandler {
    pub fn new() -> Result<Self> {
        println!("🔧 Initializing global hotkey manager...");
        let manager = GlobalHotKeyManager::new()
            .map_err(|e| anyhow!("Failed to create hotkey manager: {}", e))?;
        
        let hotkey = HotkeyBuilder::build_default()?;
        println!("📌 Registering hotkey: Cmd+Option+Shift+T (ID: {:?})", hotkey.id());
        
        manager.register(hotkey)
            .map_err(|e| anyhow!("Failed to register hotkey: {}", e))?;
        
        println!("✅ Hotkey registered successfully");
        
        Ok(Self { _manager: manager, hotkey })
    }
    
    pub fn check_pressed(&self) -> bool {
        if let Ok(event) = global_hotkey::GlobalHotKeyEvent::receiver().try_recv() {
            println!("🔑 Hotkey event detected: {:?} for ID: {:?}", event.state, event.id);
            if event.state == HotKeyState::Pressed && event.id == self.hotkey.id() {
                println!("⚡ Hotkey matched!");
                return true;
            }
        }
        false
    }
}

struct HotkeyBuilder;

impl HotkeyBuilder {
    fn build_default() -> Result<HotKey> {
        let modifiers = Modifiers::META | Modifiers::ALT | Modifiers::SHIFT;
        let code = Code::KeyT;
        
        Ok(HotKey::new(Some(modifiers), code))
    }
}