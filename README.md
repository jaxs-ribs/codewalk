# Phase 1: Terminal STT (Speech-to-Text) Clipboard

## Overview
This is Phase 1 of the CodeWalk project - a terminal-based speech-to-text application that captures audio input and converts it to text for clipboard operations. This phase establishes the foundation for voice-driven code documentation and development.

## Purpose
Phase 1 focuses on building the core STT functionality as a standalone terminal application. This serves as:
- A proof of concept for the voice input system
- The foundation for future GUI enhancements
- A working tool for developers who prefer terminal interfaces

## Features
- Global hotkey support - works from anywhere on macOS
- Automatically transcribes using Groq Whisper API
- Copies to clipboard instantly
- Two modes: Interactive (terminal) and Global (background)
- Real-time visual feedback in terminal UI

## Setup

1. Get a Groq API key from [console.groq.com/keys](https://console.groq.com/keys)

2. Create `.env` file:
```
GROQ_API_KEY=your_groq_api_key_here
```

3. Build:
```bash
cargo build --release
```

## Usage

### Interactive Mode (Terminal only)
```bash
cargo run
```
- **SPACE** - Toggle recording on/off (only when terminal is focused)
- **Q** - Quit

### Global Mode (Works from anywhere!)
```bash
cargo run -- --global
```
- **Cmd+Shift+Option+Space** - Toggle recording from anywhere
- **Ctrl+C** - Quit (in terminal)

## macOS Permissions Required

For global mode to work:
1. Go to **System Preferences → Security & Privacy → Privacy → Accessibility**
2. Click the lock to make changes
3. Add **Terminal.app** (or iTerm2, or your terminal)
4. You may need to restart the terminal

## Why This Phase?
This terminal implementation serves as the foundation for the entire CodeWalk project. By starting with a minimal, functional terminal app, we:
- Validate the core STT technology
- Establish the audio processing pipeline
- Create a working tool that's immediately useful
- Build a solid base for the GUI version in Phase 2

## Technical Stack
- **Language**: Rust
- **Audio**: cpal for cross-platform audio capture
- **STT**: Groq Whisper API
- **UI**: ratatui for terminal interface
- **Clipboard**: arboard for clipboard operations
- **Hotkeys**: rdev for global hotkey support

## Development Status
✅ Complete and functional - This phase is feature-complete and serves as the foundation for Phase 2.

## Next Steps
See Phase 2 (`phase-2-tauri-app` branch) for the Tauri-based GUI version with:
- Native desktop application
- Enhanced user interface
- Additional features and integrations
- Better user experience

## Troubleshooting

If global hotkey doesn't work:
- Make sure you granted Accessibility permissions
- Try restarting your terminal
- Check that no other app is using the same hotkey

## License
MIT