# TUI Voice Assistant

A terminal UI application with integrated voice recording and transcription using Groq's Whisper API.

## Features

- **Voice Recording**: Press Ctrl+R to start/stop recording
- **Real-time Transcription**: Audio is transcribed using Groq's Whisper API
- **Plan Creation**: Convert voice or text input into executable plans
- **Clean UI**: Split panes showing output, help, and input

## Setup

1. Get a Groq API key from [console.groq.com](https://console.groq.com)

2. Create a `.env` file:
```bash
cp .env.example .env
# Edit .env and add your GROQ_API_KEY
```

3. Build and run:
```bash
cargo build --release
cargo run
```

## Usage

- **Ctrl+R**: Toggle voice recording (press to start, press again to finalize)
- **Enter**: Submit typed text or confirm pending plan
- **Esc**: Cancel recording or pending plan
- **Ctrl+C**: Quit application

## Voice Recording Flow

1. Press Ctrl+R to start recording
2. Speak your command
3. Press Ctrl+R again to stop and transcribe
4. The transcribed text appears in the output pane
5. Use the transcribed text to create plans or take actions

## Architecture

The application is modularly structured following Clean Code principles:

- `app.rs` - Application state and business logic
- `audio.rs` - Audio recording with cpal
- `groq.rs` - Groq Whisper API client
- `backend.rs` - Integration layer for audio and API
- `ui/` - Terminal UI components
- `handlers.rs` - Input handling
- `config.rs` - Configuration management

## Requirements

- Rust 1.70+
- Working microphone
- Groq API key
- macOS, Linux, or Windows