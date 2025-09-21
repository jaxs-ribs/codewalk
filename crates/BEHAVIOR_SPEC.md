# Workstation Behavior Specification

This document describes WHAT the workstation does, not HOW it's implemented. This is the functional behavior that must be preserved in any rewrite.

## Core Purpose

The workstation orchestrates AI-assisted coding sessions by:
1. Receiving commands via voice or text
2. Routing commands to appropriate actions
3. Managing AI executor sessions (Claude, Devin, etc.)
4. Providing real-time feedback and status

## Input Sources

### 1. Voice Input (Mobile)
- Mobile app records audio
- Sends audio to workstation for STT processing
- Workstation transcribes and routes as text command

### 2. Text Input (Mobile)
- Mobile app sends text commands directly
- Treated same as transcribed voice

### 3. TUI Input (Local)
- Keyboard input for text commands
- Ctrl+R for voice recording (local mic)
- Enter to submit, Escape to cancel

## Command Routing Behavior

### The Router
- **Input**: Text command + context (active session or not)
- **Process**: LLM analyzes intent
- **Output**: One of these actions:
  - `LaunchClaude` - Start new Claude session
  - `QueryExecutor` - Get status of running executor
  - `PassThrough` - Send to active executor
  - Informational response

### Routing Logic
```
IF no active session:
  - "what are you doing?" → Check last session, respond with status
  - "launch claude to X" → Request confirmation to launch
  - Other → Contextual response

IF active session:
  - "what are you doing?" → Query active executor for status
  - Task-related → Pass through to executor
  - Meta-questions → Handle locally
```

## Executor Lifecycle

### 1. Launch Request
- Router determines launch needed
- System sends `PromptConfirmation` to all clients
- Waits for user confirmation

### 2. Confirmation Flow
- User confirms (Enter/accept) → Launch executor
- User declines (Escape/decline) → Cancel, return to idle
- Confirmation tracked by unique ID for correlation

### 3. Execution
- Executor process starts (Claude, Devin, etc.)
- Output streamed in real-time
- Session logs captured and persisted
- Session ID captured from executor output

### 4. During Execution
- User can query status ("what are you doing?")
- System summarizes current activity using logs
- User can send follow-up instructions
- User can cancel (Escape key)

### 5. Completion
- Executor finishes task
- Session marked complete
- Logs saved to artifacts/
- Summary generated and cached

## Session Management

### Session Identity
- Format: `YYYYMMDD_HHMMSS_XXXXXX`
- Generated at launch time
- Captured from executor output when available

### Session Persistence
- Logs saved to `artifacts/<session_id>/`
- Includes: logs.json, logs.txt, metadata.json
- Saves periodically during execution
- Final save on completion

### Session History
- Last session summary cached in memory
- Can query "what did you just do?"
- Time-aware responses:
  - < 1 min: "I just finished..."
  - < 5 min: "A few minutes ago, I..."
  - < 1 hour: "Earlier, I..."
  - Older: "Previously, I..."

## Status Queries

### Active Session Status
- Summarizes current logs using LLM
- Returns conversational summary
- Cached for 10 seconds to reduce API calls
- Example: "I'm currently implementing the authentication fix you requested..."

### No Active Session
- Checks last completed session
- Returns time-aware summary
- Falls back to "I'm not working on anything right now"

## User Interface Behaviors

### TUI Display
- Shows command output stream
- Shows executor output when running
- Shows confirmation prompts
- Scrollable output (arrows, page up/down)
- Recording indicator when capturing audio

### Mobile Updates
- Receives all status messages
- Receives confirmation requests
- Can fetch recent logs on demand
- Gets real-time executor status

### Relay Connection
- Auto-connects if configured
- Auto-reconnects on disconnect
- Maintains session across reconnects
- Heartbeat keeps connection alive

## Error Handling

### STT Failures
- Show error to user
- Return to idle state
- Don't crash

### Executor Launch Failures
- "Command not found" → Suggest installation
- Other errors → Show error details
- Return to idle state

### Router Failures
- Log error
- Show generic message
- Don't block user input

### Relay Disconnections
- Attempt reconnection
- Continue local operation
- Queue messages if needed

## Special Behaviors

### Log Summarization
- Uses Groq LLM API
- Extracts key activities from logs
- Provides conversational summary
- Focuses on WHAT not HOW

### Audio Processing
- Minimum 1000 bytes for valid audio
- Empty recording → "No audio detected"
- Uses backend API for STT

### Confirmation IDs
- Unique per confirmation request
- Prevents double-processing
- Allows correlation across clients

## State Indicators

### User-Visible States
- **Ready/Idle** - Waiting for commands
- **Recording** - Capturing audio
- **Confirming** - Waiting for launch confirmation
- **Running** - Executor active
- **Error** - Showing error dialog

### Background States
- Session tracking
- Relay connection status
- Cache timers
- Log persistence

## Performance Behaviors

### Polling Frequencies
- Executor output: 10 messages per poll
- Relay messages: 10 per poll
- Core state: Every loop iteration
- No blocking waits

### Caching
- Session summaries: 10 seconds
- Last session: Until next session
- Log batching: Every 10 logs

### Persistence
- Logs: Every 10 entries or on important events
- Metadata: On session start
- Final save: On session end

## Concurrency

### Parallel Operations
- Relay connection independent
- STT processing async
- Log summarization async
- Multiple clients supported

### Serial Operations
- One executor at a time
- Confirmations processed in order
- State transitions atomic

## Configuration

### Environment Variables
- `ANTHROPIC_API_KEY` - For Claude
- `GROQ_API_KEY` - For summarization
- `RELAY_*` - For mobile connection
- `RUST_LOG` - For debug logging

### Defaults
- Working directory: Current directory
- Artifacts: `./artifacts/`
- Max output lines: Configured limit
- Scroll behavior: Auto-scroll on