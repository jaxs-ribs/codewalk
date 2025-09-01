# VoiceRelay SwiftUI

iOS voice transcription client with WebSocket relay connectivity.

## Architecture

```
ContentView (UI)
    ├── RelayWebSocket → Relay Server (WebSocket JSON)
    ├── Recorder → WAV files (16kHz mono PCM)  
    └── STTUploader → Groq Whisper API
```

## Core Components

**ContentView** - Main UI with dark glassmorphic design. Manages recording state machine and displays connection status/logs.

**RelayWebSocket** - WebSocket client with auto-reconnect, heartbeat (30s), and typed message routing. Sends `hello` on connect.

**Recorder** - AVAudioRecorder wrapper producing 16kHz WAV files optimized for Whisper.

**STTUploader** - Multipart form uploader to Groq's transcription endpoint. Low-memory streaming.

**EnvConfig** - Loads `.env` from bundle or environment variables.

## Quick Start

```bash
# Terminal A - Start relay server
cd relay/server && cargo run --release --bin relay-server

# Terminal B - Run iOS app  
cd apps/VoiceRelaySwiftUI && ./run-sim.sh
```

## Setup

1. **Environment** - Create `.env` at repo root:
```
GROQ_API_KEY=your_key
RELAY_WS_URL=ws://127.0.0.1:3001
RELAY_SESSION_ID=your_session
RELAY_TOKEN=your_token
```

2. **Dependencies**:
- Xcode 15+, iOS 16+
- `brew install xcodegen`

3. **Run**: `./run-sim.sh` handles everything (project generation, build, simulator launch)

## Protocol

**Send:**
```json
{"type": "hello", "session_id": "...", "token": "..."}
{"type": "user_text", "text": "...", "final": true, "source": "stt"}
{"type": "request_logs"}
```

**Receive:**
```json
{"type": "event", "event": "...", "payload": {...}}
{"type": "ack", "id": "..."}
{"type": "logs", "logs": [...]}
```

## Recording Flow

```
idle → recording → uploading → transcribing → sending → idle
                ↘ cancel ↗
```

## Files

- `ContentView.swift` - UI and state management
- `RelayWebSocket.swift` - WebSocket connection logic
- `Recorder.swift` - Audio recording
- `STTUploader.swift` - Groq API integration  
- `EnvConfig.swift` - Configuration loader
- `project.yml` - XcodeGen project definition
- `run-sim.sh` - Build and launch script

## Troubleshooting

- **Black screen**: Simulator needs reboot
- **Can't connect**: Use `127.0.0.1` not `localhost`
- **No transcript**: Speak clearly, check Groq API key
- **Mic permission**: App prompts for Settings access