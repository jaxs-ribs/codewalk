# Frozen Contracts & External Dependencies

This document identifies all interfaces and dependencies that CANNOT change or that we depend on externally.

## FROZEN: Mobile Interface

**Status**: ⛔ FROZEN - Cannot change without breaking mobile app

See `MOBILE_INTERFACE_SPEC.md` for details. Summary:
- Protocol message shapes (UserText, ConfirmResponse, etc.)
- Relay WebSocket protocol
- STT request/response format
- Log fetching format

## FROZEN: Protocol Messages

**Status**: ⛔ FROZEN - Version 1 is locked

Location: `crates/protocol/src/lib.rs`

```rust
pub enum Message {
    UserText(UserText),
    Ack(Ack),
    Status(Status),
    PromptConfirmation(PromptConfirmation),
    ConfirmResponse(ConfirmResponse),
}
```

Fields, types, and JSON serialization format are frozen.

## EXTERNAL: Claude Executor

**Status**: 🔒 External dependency

Interface:
- Launch via: `claude --mcp-server <args>`
- Input: Initial prompt string
- Output: Stream-JSON format lines
- Session ID: Captured from output

Required environment:
- `ANTHROPIC_API_KEY` must be set

Message format (stream-json):
```json
{"type": "user_message", "content": "..."}
{"type": "assistant_message", "content": "..."}
{"type": "tool_use", ...}
{"type": "tool_result", ...}
{"session_id": "..."}
```

## EXTERNAL: Router (LLM)

**Status**: 🔒 External dependency

Current implementation uses Anthropic API directly.

Interface:
```rust
RouterContext {
    has_active_session: bool,
    session_type: Option<String>,
    last_command: Option<String>,
}

RouteDecision {
    action: RouteAction,
    reasoning: Option<String>,
    prompt: Option<String>,
}

enum RouteAction {
    LaunchClaude,
    QueryExecutor,
    PassThrough,
}
```

Required environment:
- `ANTHROPIC_API_KEY` must be set

## EXTERNAL: STT Backend

**Status**: 🔒 External dependency

Current implementation uses Groq Whisper API.

Interface:
- Input: Raw audio bytes (WAV format typical)
- Output: Transcribed text string
- Async processing

Required environment:
- `GROQ_API_KEY` must be set

API endpoint:
- `https://api.groq.com/openai/v1/audio/transcriptions`

## EXTERNAL: Log Summarizer

**Status**: 🔒 External dependency

Uses Groq LLM for log summarization.

Interface:
- Input: Array of log entries
- Output: Conversational summary string
- Model: `llama-3.3-70b-versatile`

Required environment:
- `GROQ_API_KEY` must be set

## EXTERNAL: Relay Server

**Status**: 🔒 External infrastructure

WebSocket relay server for mobile ↔ workstation communication.

Configuration via environment:
```bash
RELAY_WS_URL=wss://relay.example.com/v1/session
RELAY_SESSION_ID=<session_id>
RELAY_AUTH_TOKEN=<auth_token>
RELAY_HEARTBEAT_SECS=30
```

Protocol:
- WebSocket text frames
- JSON messages
- Hello/hello-ack handshake
- Frame wrapping for app messages

## SEMI-FROZEN: Session ID Format

**Status**: ⚠️ Semi-frozen - Mobile app expects this pattern

Format: `YYYYMMDD_HHMMSS_XXXXXX`
- Date/time prefix
- 6 random alphanumeric suffix
- Example: `20240115_143022_abc123`

Can add additional session ID formats but must support this one.

## SEMI-FROZEN: Artifact Storage

**Status**: ⚠️ Semi-frozen - Path structure expected

Location: `./artifacts/<session_id>/`

Files:
- `metadata.json` - Session metadata
- `logs.json` - Structured logs
- `logs.txt` - Human-readable logs
- `status.json` - Session status

Can add new files but must maintain these.

## CONFIGURATION: Environment Variables

**Status**: 📝 Configuration interface

Required:
- `ANTHROPIC_API_KEY` - For Claude and routing
- `GROQ_API_KEY` - For STT and summarization

Optional:
- `RELAY_WS_URL` - Relay WebSocket URL
- `RELAY_SESSION_ID` - Session identifier
- `RELAY_AUTH_TOKEN` - Auth token
- `RELAY_HEARTBEAT_SECS` - Heartbeat interval
- `RUST_LOG` - Logging level

## BEHAVIORAL: Confirmation Flow

**Status**: ⚠️ Behavioral contract

1. System sends `PromptConfirmation` with unique ID
2. User responds with `ConfirmResponse` matching ID
3. System proceeds only if `accept: true`

Mobile app expects this exact flow.

## BEHAVIORAL: Status Query Response

**Status**: ⚠️ Behavioral contract

When asked "what are you doing?":
- With active session: Return current activity summary
- Without session: Return last session summary or "not working"

Mobile app expects meaningful status responses.

## LIBRARY DEPENDENCIES

**Status**: 📦 External crates

Core dependencies (from workspace):
- `tokio` - Async runtime
- `serde` / `serde_json` - Serialization
- `anyhow` - Error handling
- `async-trait` - Async traits
- `clap` - CLI parsing
- `reqwest` - HTTP client
- `base64` - Encoding

TUI dependencies:
- `ratatui` - Terminal UI
- `crossterm` - Terminal control

Cannot change tokio runtime or serde serialization without major impact.

## Summary of Constraints

### Absolutely Frozen ⛔
1. Mobile protocol messages
2. Relay WebSocket protocol
3. Protocol v1 message shapes

### External Dependencies 🔒
1. Claude executor interface
2. Groq API (STT & summarization)
3. Anthropic API (routing)
4. Relay server

### Semi-Frozen ⚠️
1. Session ID format
2. Artifact storage structure
3. Confirmation flow
4. Status query behavior

### Configuration 📝
1. Environment variables
2. API keys
3. Relay settings

## Migration Notes

When rewriting, we MUST:
1. Preserve all frozen interfaces exactly
2. Support all external dependency interfaces
3. Maintain behavioral contracts
4. Keep configuration compatibility

We CAN:
1. Change internal architecture completely
2. Add new features/states
3. Improve error handling
4. Optimize performance
5. Add new frontends
6. Extend protocols (with versioning)