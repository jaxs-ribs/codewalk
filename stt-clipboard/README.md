# STT-Clipboard

Minimal speech-to-text tool that copies transcriptions directly to clipboard.

## Features
- Global hotkey support - works from anywhere on macOS
- Automatically transcribes using Groq Whisper API
- Copies to clipboard instantly
- Two modes: Interactive (terminal) and Global (background)

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

## Why Cmd+Shift+Option+Space?

This combination is unlikely to conflict with any existing shortcuts:
- Most apps don't use all three modifiers + Space
- It's still easy to press with one hand
- Works globally across all applications

## Troubleshooting

If global hotkey doesn't work:
- Make sure you granted Accessibility permissions
- Try restarting your terminal
- Check that no other app is using the same hotkey