# CodeWalk - Modular Voice Assistant TUI

A modular terminal UI application with voice recording and command planning capabilities.

## End-to-End Flow (Relay + Mobile + Orchestrator)

This repo includes:
- Relay server at `relay/server`
- Mobile app at `apps/VoiceRelay`
- Workstation TUI (orchestrator) at `crates/orchestrator` (binary `codewalk`)

Setup (.env at repo root)

Create `./.env` with a single source of truth used by server, app, and orchestrator:

RELAY_WS_URL=ws://127.0.0.1:3001/ws
RELAY_SESSION_ID=dev-session-123
RELAY_TOKEN=dev-token-abc
# Optional (enables voice/LLM in TUI)
# GROQ_API_KEY=your_key

Run Order (four terminals)

1) Relay server

   cd relay/server
   PUBLIC_WS_URL=ws://127.0.0.1:3001/ws \
   cargo run --release --bin relay-server

2) Mobile app

   # Terminal A (Metro)
   cd apps/VoiceRelay && npm install && nvm use && npm start
   # Terminal B (Simulator)
   cd apps/VoiceRelay && npm run ios -- --simulator="iPhone 16 Pro"

3) Orchestrator (workstation TUI)

   cargo run -p orchestrator --bin codewalk

4) Send a message from the phone

- Type a message in the app and press Send.
- Expectation: the TUI shows `RELAY> ...` lines for status and the incoming note. The app shows `Ack: received`.

Notes
- Orchestrator connects to the relay on startup when `RELAY_SESSION_ID` and `RELAY_TOKEN` are set. If `GROQ_API_KEY` is unset, voice/LLM features are disabled but the TUI still runs to show relay traffic.
- For setup details and troubleshooting, see `apps/VoiceRelay/README.md` and `relay/server/README.md`.
 - If the app shows “Health: configure RELAY_WS_URL in .env”, ensure `.env` exists at repo root, run `npm install` in `apps/VoiceRelay`, and restart Metro with `npm start -- --reset-cache`.

## Architecture

The project is organized as a Rust workspace with three independent crates:

### 1. `audio-transcribe`
**Purpose**: Audio recording and transcription services

- **Trait-based design**: `TranscriptionProvider` trait allows swapping between different services
- **Current providers**: Groq (Whisper API)
- **Future providers**: OpenAI, local Whisper, Deepgram, etc.

Key components:
- `AudioRecorder`: Hardware audio capture using cpal
- `TranscriptionProvider` trait: Service-agnostic interface
- Provider implementations in `providers/`

### 2. `llm-interface`
**Purpose**: Text-to-command planning and extraction

- **Trait-based design**: `LLMProvider` and `PlanExtractor` traits
- **Current providers**: Mock provider for testing
- **Future providers**: GPT-4, Claude, Llama, local models

Key components:
- `LLMProvider` trait: Convert text to structured plans
- `PlanExtractor` trait: Extract commands from JSON responses
- `CommandPlan` types: Structured representation of plans

### 3. `tui-app`
**Purpose**: Terminal UI application

- Uses the other crates through trait interfaces
- Completely agnostic to which services are used
- Easy to swap providers via configuration

## Setup

1. Get a Groq API key from [console.groq.com](https://console.groq.com)

2. Set your API key in environment:
```bash
export GROQ_API_KEY=your_key_here
```

3. Run:
```bash
cargo run
```

## Usage

- **Ctrl+R**: Toggle voice recording
- **Enter**: Submit text or confirm plan
- **Esc**: Cancel operation
- **Ctrl+C**: Quit

## Swapping Providers

The modular design makes it trivial to swap services:

### Example: Adding OpenAI Transcription

1. Implement the trait in `audio-transcribe/src/providers/openai.rs`:
```rust
impl TranscriptionProvider for OpenAIProvider {
    async fn transcribe(&self, audio_data: Vec<u8>) -> Result<TranscriptionResult> {
        // Your OpenAI implementation
    }
}
```

2. Update backend initialization in `tui-app/src/backend.rs`:
```rust
// Simply swap the provider
let mut provider = Box::new(OpenAIProvider::new());
```

### Example: Adding GPT-4 for Planning

1. Implement in `llm-interface/src/providers/openai.rs`:
```rust
impl LLMProvider for GPT4Provider {
    async fn text_to_plan(&self, text: &str) -> Result<String> {
        // Your GPT-4 implementation
    }
}
```

2. Swap in the backend - no other code changes needed!

## Benefits of This Architecture

1. **Service Independence**: Not locked into any specific API
2. **Easy Testing**: Mock providers for unit tests
3. **Cost Optimization**: Switch between providers based on cost/quality
4. **Fallback Support**: Can implement fallback chains
5. **Local-First Option**: Easy to add local model support
6. **Clean Separation**: Each crate has a single responsibility

## Development

### Adding a New Transcription Service

1. Add provider in `audio-transcribe/src/providers/`
2. Implement `TranscriptionProvider` trait
3. Update backend configuration

### Adding a New LLM Service  

1. Add provider in `llm-interface/src/providers/`
2. Implement `LLMProvider` trait
3. Update backend configuration

### Running Tests

```bash
# Test individual crates
cargo test -p audio-transcribe
cargo test -p llm-interface
cargo test -p tui-app

# Test everything
cargo test --workspace
```

## License

MIT
