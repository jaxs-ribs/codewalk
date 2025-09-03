# Orchestrator - Voice-Driven AI Assistant Controller

The Orchestrator is the central hub of the VoiceAgent system, managing voice commands, routing decisions, and coordinating AI executor sessions (Claude Code, etc.). It acts as a bridge between mobile voice interfaces and AI coding assistants.

## Architecture Overview

```
┌─────────────────┐         WebSocket          ┌──────────────────┐
│                 │◄──────────────────────────►│                  │
│   VoiceAgent    │         Messages           │   Relay Server   │
│   (Mobile App)  │                            │   (Port 3001)    │
└─────────────────┘                            └──────────────────┘
                                                         ▲
                                                         │
                                                    WebSocket
                                                         │
                                                         ▼
                                              ┌──────────────────┐
                                              │                  │
                                              │   Orchestrator   │
                                              │                  │
                                              └──────────────────┘
                                                         │
                                              ┌──────────┴───────────┐
                                              │                      │
                                         ┌────▼──────┐      ┌────────▼────────┐
                                         │           │      │                 │
                                         │   Groq    │      │  Claude Code    │
                                         │   Router  │      │    Executor     │
                                         │   (LLM)   │      │                 │
                                         └───────────┘      └─────────────────┘
```

## Core State Machine

The Orchestrator operates as a state machine with clear transitions based on user input and system events:

```
                            ┌─────────┐
                            │  IDLE   │◄───────────────────┐
                            └────┬────┘                    │
                                 │                         │
                         User speaks command               │
                                 │                         │
                                 ▼                         │
                        ┌──────────────────┐              │
                        │  ROUTING         │              │
                        │  (LLM Analysis)  │              │
                        └────────┬─────────┘              │
                                 │                         │
                ┌────────────────┼────────────────┐       │
                │                │                │       │
           Launch Claude    Query Status    Cannot Parse  │
                │                │                │       │
                ▼                ▼                ▼       │
         ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
         │ CONFIRMING  │  │ SUMMARIZING │  │  ERROR   │ │
         │  EXECUTOR   │  │   SESSION   │  │ DISPLAY  │ │
         └─────┬───────┘  └──────┬──────┘  └─────┬────┘ │
               │                  │                │      │
         Yes/No spoken      Summary sent     User dismisses
               │                  │                │      │
      ┌────────┴────────┐         └────────────────┴──────┘
      │                 │
   Accept           Reject
      │                 │
      ▼                 │
┌──────────────┐        │
│   EXECUTOR   │        │
│   RUNNING    │        │
└──────┬───────┘        │
       │                │
  Session ends          │
       └────────────────┘
```

## Detailed State Descriptions

### 1. **IDLE State**
- **Description**: System awaits user input
- **Entry**: System startup, command completion, error dismissal
- **Actions**: Listening for voice commands via mobile app
- **Exit**: User speaks a command

### 2. **ROUTING State**
- **Description**: LLM analyzes user intent
- **Entry**: Voice command received
- **Processing**: Groq/Llama model determines action
- **Outputs**:
  - `LaunchClaude`: User wants to code/build something
  - `QueryExecutor`: User asks about session status
  - `CannotParse`: Command not understood

### 3. **CONFIRMING_EXECUTOR State**
- **Description**: Awaiting user confirmation for Claude Code launch
- **Entry**: Router decides to launch executor with confirmation required
- **UI**: Mobile app speaks "Do you want me to start a Claude Code session for: [task]? Yes or no"
- **Exits**:
  - Yes → Launch executor
  - No → Return to IDLE
  - Timeout → Return to IDLE

### 4. **EXECUTOR_RUNNING State**
- **Description**: Claude Code actively working on task
- **Entry**: User confirms or auto-launch without confirmation
- **Features**:
  - Real-time log streaming
  - Session tracking with unique IDs
  - Progress monitoring
- **Exit**: Task completes or user cancels

### 5. **SUMMARIZING State**
- **Description**: Generating status summary
- **Entry**: User asks "What's happening?" or similar
- **Processing**:
  - Active session: Summarize current logs via Groq
  - No session: Report last session history
  - Cache hit: Return cached summary (10s TTL)
- **Exit**: Summary delivered to user

## Message Protocol

The system uses typed JSON messages for all communication:

### User → Orchestrator
```json
{
  "type": "user_text",
  "text": "help me fix the router bug",
  "is_final": true
}
```

### Orchestrator → User (Confirmation)
```json
{
  "type": "prompt_confirmation",
  "id": "confirm_123",
  "for": "executor_launch",
  "executor": "Claude",
  "prompt": "help me fix the router bug"
}
```

### User → Orchestrator (Response)
```json
{
  "type": "confirm_response",
  "id": "confirm_123",
  "accept": true
}
```

### Orchestrator → User (Status)
```json
{
  "type": "status",
  "level": "info",
  "text": "Starting Claude Code for: help me fix the router bug"
}
```

## Key Features

### 1. **Intelligent Routing**
Uses Groq's Llama 3.1 model for natural language understanding:
- Detects coding intent ("build", "fix", "implement", etc.)
- Recognizes status queries ("what's happening", "status", etc.)
- Context-aware (knows if session is active)

### 2. **Session Management**
- **Unique IDs**: Each Claude session gets timestamp-based ID
- **Log Persistence**: Sessions saved to `artifacts/` directory
- **History Tracking**: Remembers last session for context

### 3. **Smart Summaries**
- **Active Sessions**: Real-time progress summaries via Groq
- **Session History**: "Previously, Claude fixed the authentication bug"
- **Caching**: 10-second cache prevents redundant API calls

### 4. **Confirmation Flow**
- **Voice Confirmation**: Yes/no recognition with LLM fallback
- **Prompt Echo**: Confirms actual task, not generic message
- **Timeout Handling**: Auto-cancels if no response

## Configuration

### Environment Variables (.env)
```bash
# Groq API for routing and summaries
GROQ_API_KEY=your_key_here

# Relay server connection
RELAY_WS_URL=ws://127.0.0.1:3001/ws
RELAY_SESSION_ID=devsession0001
RELAY_TOKEN=devtoken0001x

# Executor settings
REQUIRE_CONFIRMATION=true  # Ask before launching Claude
```

### Settings (settings.yaml)
```yaml
require_executor_confirmation: true
default_executor: claude
working_dir: /tmp/claude_workspace
```

## File Structure

```
orchestrator/
├── src/
│   ├── main.rs           # Entry point, TUI setup
│   ├── app.rs            # Core state machine
│   ├── backend.rs        # Groq integration
│   ├── relay_client.rs   # WebSocket to relay
│   ├── core_bridge.rs    # Protocol adaptation
│   ├── log_summarizer.rs # Session summaries
│   ├── logger.rs         # File logging
│   └── types.rs          # State definitions
├── logs/                  # Runtime logs
│   └── orchestrator_*.log
├── artifacts/            # Session histories
│   └── [session_id]/
│       ├── metadata.json
│       └── logs.jsonl
└── Cargo.toml
```

## Running the Orchestrator

### Prerequisites
1. Rust toolchain installed
2. Groq API key configured
3. Relay server running on port 3001

### Build and Run
```bash
# Development mode with TUI
cd crates/orchestrator
cargo run

# Release build
cargo build --release
./target/release/orchestrator

# Headless mode (no TUI)
cargo run --no-default-features
```

### Testing States

1. **Test Routing**:
   ```
   Say: "Help me build a web server"
   Expected: Confirmation prompt
   ```

2. **Test Confirmation**:
   ```
   Say: "Yes" after prompt
   Expected: "Starting Claude Code for: help me build a web server"
   ```

3. **Test Status Query**:
   ```
   Say: "What's happening?"
   Expected: Summary of current or last session
   ```

4. **Test Cancellation**:
   ```
   Say: "No" to confirmation
   Expected: Return to idle
   ```

## Debugging

### Log Files
Check `logs/orchestrator_[timestamp].log` for:
- State transitions
- Router decisions
- API calls
- Error traces

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "No Groq API key" | Missing GROQ_API_KEY | Set in .env file |
| Can't connect to relay | Relay not running | Start relay-server first |
| Router always says "cannot parse" | API quota exceeded | Check Groq dashboard |
| No audio from mobile | Orchestrator not forwarding | Check relay connection |

## Advanced Features

### Custom Executors
The system supports multiple AI executors through the `ExecutorPort` trait:
```rust
trait ExecutorPort {
    async fn launch(&self, prompt: &str) -> Result<()>;
    async fn query_status(&self) -> Result<String>;
}
```

### Router Context
The router receives context about active sessions:
```json
{
  "has_active_session": true,
  "session_type": "claude"
}
```

### Session Artifacts
Each session saves:
- Full command logs
- Parsed structured events
- Metadata (prompt, duration, etc.)
- LLM-generated summaries

## Contributing

The orchestrator is designed for extensibility:
- Add new executors in `control-center/`
- Customize routing in `router/providers/groq.rs`
- Enhance summaries in `log_summarizer.rs`
- Add new states in `types.rs`

## Architecture Principles

1. **State-Driven**: Clear states with defined transitions
2. **Event-Based**: Async message passing between components
3. **Fail-Safe**: Graceful degradation without APIs
4. **Observable**: Comprehensive logging and artifacts
5. **Extensible**: Trait-based executor abstraction