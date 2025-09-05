# Codewalk Project Information for AI Agents

## Important Directories

### Logs
- **Orchestrator logs**: `artifacts/orchestrator_*.log` (in project root)
  - Format: `orchestrator_YYYYMMDD_HHMMSS.log`
  - Contains routing decisions, session management, and debug info
  
- **Mobile app logs**: 
  - VoiceAgent: `apps/VoiceAgent/logs/`
  - VoiceRelaySwiftUI: `apps/VoiceRelaySwiftUI/app_debug.log`

### Key Source Locations
- **Orchestrator**: `crates/orchestrator/src/`
  - Main app: `app.rs`
  - Confirmation handling: `confirmation_handler.rs`
  - Core bridge: `core_bridge.rs`
  
- **Router**: `crates/router/src/`
  - Confirmation analysis: `confirmation.rs`
  
- **Mobile Apps**: `apps/`
  - VoiceAgent (iOS)
  - VoiceRelaySwiftUI (macOS)

## Common Issues & Debugging

### "Query Status" Loop
- Check orchestrator logs for routing decisions
- Verify Mode state (should be ConfirmingExecutor after LaunchClaude)
- Check if messages are going through LLM instead of local confirmation handler

### Building & Running
```bash
# Build orchestrator
cargo build -p orchestrator --release  # or without --release for debug

# Run orchestrator
./target/release/codewalk  # or ./target/debug/codewalk

# Check logs
tail -f artifacts/orchestrator_*.log
```

### Testing Confirmation Flow
1. Send a command that triggers Claude (e.g., "help me with a coding task")
2. Orchestrator should enter ConfirmingExecutor mode
3. Responses should be handled by local confirmation analyzer, not LLM

## Key Components

### Session Management
- Sessions tracked with UUIDs
- Resume capability with `--resume <session_id>` flag
- Session summaries stored for context

### Message Flow
1. User input → Relay → Orchestrator
2. Orchestrator routes through core or handles directly
3. Core uses RouterAdapter → LLM for routing
4. Confirmation responses intercepted before LLM

### Voice Settings
- ElevenLabs TTS voice IDs configured in:
  - `apps/VoiceAgent/Sources/ElevenLabsTTS.swift`
  - `apps/VoiceRelaySwiftUI/Sources/ElevenLabsTTS.swift`
