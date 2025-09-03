# Session Management Testing Instructions

## Overview
The orchestrator now properly tracks and distinguishes between current and previous sessions. When queried about session status, it will clearly specify whether it's describing a current active session or a previous completed session.

## Key Improvements Made

1. **Session Tracking**: 
   - Captures session ID when Claude starts
   - Tracks session start time and duration
   - Saves session metadata to `artifacts/session_<id>/`

2. **Status Responses**:
   - **Current session**: "Current session (ID: abc123, running for 45s): Claude is working on..."
   - **Previous session**: "Previous session completed X minutes ago: Claude helped with..."
   - **No sessions**: "No active session. No previous sessions found."

3. **Persistence**:
   - Session metadata saved to disk in JSON format
   - Session logs saved in both JSON and human-readable text
   - Metadata includes: session ID, status, summary, completion time, duration

## Manual Testing Steps

### Step 1: Build the Orchestrator
```bash
cargo build -p orchestrator
```

### Step 2: Start the Orchestrator
```bash
./target/debug/orchestrator
```

### Step 3: Test Session Queries

#### Test A: Query with No Active Session
1. In the orchestrator, type: `what's happening`
2. Expected response: "No active session" or info about a previous session if one exists

#### Test B: Start a Claude Session
1. Type: `help me write a hello world function`
2. Wait for Claude to start (you'll see "Captured Claude session ID: ...")
3. Note the session ID shown

#### Test C: Query During Active Session
1. While Claude is working, type: `what's the status`
2. Expected response: "Current session (ID: <first-8-chars>, running for Xs): Claude is..."

#### Test D: Query After Session Completes
1. Wait for Claude to finish (you'll see "Claude session completed")
2. Type: `what was that about`
3. Expected response: "Previous session completed X seconds ago: ..."

### Step 4: Check Artifacts

After testing, examine the artifacts directory:
```bash
# List session directories
ls -la artifacts/session_*

# View session metadata
cat artifacts/session_*/metadata.json

# View human-readable logs
cat artifacts/session_*/logs.txt
```

## Automated Test Script

A test script is also available:
```bash
./test_session_status.sh
```

This script automates the above tests and verifies:
- Session creation and tracking
- Proper status responses
- Session completion marking
- Log and metadata persistence

## Expected Artifacts Structure

```
artifacts/
└── session_20241203_142530_a1b2c3/
    ├── metadata.json    # Session metadata with status
    ├── logs.json        # Structured logs
    └── logs.txt         # Human-readable logs
```

## Metadata Example

```json
{
  "session_id": "20241203_142530_a1b2c3",
  "status": "completed",
  "summary": "Claude helped write a hello world function in Python",
  "completed_at": "2024-12-03T14:26:15Z",
  "executor_type": "Claude",
  "duration_secs": 45
}
```

## Success Criteria

✅ Session IDs are captured and displayed
✅ Status queries clearly distinguish current vs previous sessions
✅ Session metadata is persisted to disk
✅ Previous sessions can be recalled even after restart
✅ Time information is included (duration for current, time ago for previous)