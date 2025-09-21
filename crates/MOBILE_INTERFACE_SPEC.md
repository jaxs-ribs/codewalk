# Mobile Interface Specification (FROZEN CONTRACT)

This document defines the **frozen interface** between the workstation and mobile app. These contracts MUST be maintained for backward compatibility.

## Overview

The mobile app communicates with the workstation via:
1. **WebSocket relay server** - Real-time bidirectional communication
2. **Protocol messages** - Structured JSON messages with specific schemas
3. **Special mobile-only messages** - STT requests, log fetching

## 1. WebSocket Relay Protocol

### Connection Flow
```
Mobile → Relay Server ← Workstation
```

### Relay Messages (WebSocket Layer)

#### Handshake
```json
// Workstation → Relay
{
  "type": "hello",
  "s": "session_id",
  "t": "auth_token", 
  "r": "workstation"
}

// Relay → Workstation
{
  "type": "hello-ack"
}
```

#### Connection Events
```json
// When mobile connects
{
  "type": "peer-joined",
  "role": "mobile"
}

// When mobile disconnects
{
  "type": "peer-left",
  "role": "mobile"
}

// Session terminated
{
  "type": "session-killed"
}
```

#### Frame Wrapper
All application messages are wrapped in frames:
```json
{
  "type": "frame",
  "frame": "..." // Stringified JSON of actual message
}
```

#### Heartbeat
- Sent every N seconds (configurable, min 5s)
- Format: `{"type":"hb"}`

## 2. Protocol Messages (Application Layer)

These messages are sent as stringified JSON inside relay frames.

### UserText
Mobile → Workstation
```json
{
  "type": "user_text",
  "v": 1,              // Protocol version
  "id": "msg_123",     // Optional message ID
  "text": "launch claude to fix the bug",
  "source": "mobile",  // "mobile" | "phone" | "tui" | "api"
  "final": true        // true for complete, false for streaming
}
```

### PromptConfirmation
Workstation → Mobile
```json
{
  "type": "prompt_confirmation",
  "v": 1,
  "id": "confirm_12345",        // Unique confirmation ID
  "for": "executor_launch",     // What we're confirming
  "executor": "Claude",          // Which executor
  "working_dir": "/home/user/project",  // Optional
  "prompt": "fix the authentication bug"
}
```

### ConfirmResponse
Mobile → Workstation
```json
{
  "type": "confirm_response",
  "v": 1,
  "id": "confirm_12345",    // ID of the confirmation
  "for": "executor_launch",
  "accept": true            // true to proceed, false to cancel
}
```

### Status
Workstation → Mobile
```json
{
  "type": "status",
  "v": 1,
  "level": "info",    // "info" | "warn" | "error"
  "text": "Claude session started successfully"
}
```

### Ack
Either direction (acknowledgment)
```json
{
  "type": "ack",
  "v": 1,
  "reply_to": "msg_123",  // Optional: ID of message being acknowledged
  "text": "received"
}
```

## 3. Mobile-Specific Messages

These are special messages outside the standard protocol.

### STT Request
Mobile → Workstation (requests speech-to-text processing)
```json
{
  "type": "stt_request",
  "id": "stt_123",           // Request ID for correlation
  "mime": "audio/wav",       // Audio format
  "data": "base64_encoded_audio_data..."  // Base64 encoded audio
}
```

### STT Result
Workstation → Mobile (STT processing result)
```json
{
  "type": "stt_result",
  "replyTo": "stt_123",      // Correlates to request
  "mime": "audio/wav",
  "ok": true,                // Success/failure
  "text": "transcribed text here"  // Empty if failed
}
```

### Get Logs Request
Mobile → Workstation (fetch recent logs)
```json
{
  "type": "get_logs",
  "id": "logs_456",
  "count": 50                // Number of recent lines to fetch
}
```

### Logs Response
Workstation → Mobile
```json
{
  "type": "logs",
  "replyTo": "logs_456",
  "logs": [
    "◆ Starting Claude Code for: fix the bug",
    "Claude: I'll help you fix that bug...",
    // ... array of log lines
  ]
}
```

## 4. Message Flow Patterns

### Pattern 1: Voice Command
```
1. Mobile: records audio
2. Mobile → Workstation: stt_request
3. Workstation: processes STT
4. Workstation → Mobile: stt_result
5. Workstation: routes transcribed text
6. Workstation → Mobile: prompt_confirmation (if launching executor)
7. Mobile → Workstation: confirm_response
8. Workstation → Mobile: status updates
```

### Pattern 2: Text Command
```
1. Mobile → Workstation: user_text
2. Workstation: routes command
3. Workstation → Mobile: prompt_confirmation (if launching executor)
4. Mobile → Workstation: confirm_response
5. Workstation → Mobile: status updates
```

### Pattern 3: Status Query
```
1. Mobile → Workstation: user_text ("what are you doing?")
2. Workstation: checks executor status
3. Workstation → Mobile: status (with current activity)
```

## 5. Relay Configuration

Environment variables (set on workstation):
```bash
RELAY_WS_URL=wss://relay.example.com/v1/session
RELAY_SESSION_ID=unique_session_id
RELAY_AUTH_TOKEN=auth_token
RELAY_HEARTBEAT_SECS=30
```

## 6. Critical Behaviors

### Auto-Acknowledgment
- Messages with type "note" or "user_text" trigger automatic ack
- Ack format: `{"type":"ack","replyTo":"<id>","text":"received"}`

### Frame Forwarding
- ALL protocol messages to mobile MUST be sent via `relay_client::send_frame()`
- The relay client wraps them in frame messages automatically

### Connection Resilience
- Relay client auto-reconnects on disconnect
- Heartbeat keeps connection alive
- Session persists across reconnections

## 7. Data Formats

### Audio Data
- Base64 encoded raw audio bytes
- Typically WAV format but mime type specifies actual format
- Size threshold: >1000 bytes for valid audio

### Log Lines
- Plain text strings
- May contain emoji prefixes (◆, ►, ◊, etc.)
- Newest logs at end of array

### Session IDs
- Format: `YYYYMMDD_HHMMSS_XXXXXX` (timestamp + 6 random chars)
- Example: `20240115_143022_abc123`

## 8. Error Handling

### STT Failures
- Return `ok: false` with empty text
- Log error on workstation side

### Invalid Messages
- Silently drop or log
- Don't crash or disconnect

### Connection Loss
- Auto-reconnect with exponential backoff
- Preserve session state

## Non-Negotiable Constraints

1. **Protocol version**: Currently v1, field is optional for backward compat
2. **Message shapes**: Must match exactly as specified
3. **Field names**: Case-sensitive, use snake_case
4. **WebSocket frames**: Text frames only (not binary)
5. **JSON encoding**: Standard JSON, not MessagePack or other formats
6. **Relay wrapping**: All app messages wrapped in relay frames

This interface is FROZEN and must be maintained for mobile app compatibility.