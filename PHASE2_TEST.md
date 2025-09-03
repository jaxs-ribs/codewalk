# Phase 2 Test Instructions: Orchestrator Pending State

## Overview
Phase 2 implements proper pending state management with re-prompting for ambiguous responses.

## What's Been Implemented

1. **Enhanced PendingExecutor State**:
   - Added `is_initial_prompt` flag to track if this is the first ask
   - Added `session_action` to store user's decision
   - Added `SessionAction` enum: ContinuePrevious/StartNew/Declined

2. **Confirmation Handler Module** (`confirmation_handler.rs`):
   - Handles all 5 response types when in ConfirmingExecutor mode
   - Re-prompts on ambiguous "yes" responses
   - Tracks whether it's already re-prompted once

3. **State Flow**:
   - Initial prompt: "Should I start Claude?"
   - Ambiguous response → Re-prompt: "Continue previous or start new?"
   - Second ambiguous → Treat as unintelligible
   - Clear responses → Process action

## Test Instructions

### Build and Run
```bash
cargo build -p orchestrator
./target/debug/orchestrator
```

### Test Sequence

#### Test 1: Ambiguous Response → Re-prompt
1. Type: `help me code`
2. System: "Ready to launch Claude. Press Enter to confirm..."
3. Type: `yes` (ambiguous)
4. **Expected**: 
   - "Would you like to continue your previous session or start a new one?"
   - "Say 'continue', 'new', or 'no'"

#### Test 2: Clear Response After Re-prompt
1. Follow Test 1 to get re-prompt
2. Type: `continue`
3. **Expected**: "Continuing previous session..."
4. (Note: Actual resumption will be in Phase 3)

#### Test 3: Double Ambiguous → Unintelligible
1. Type: `help me code`
2. Type: `yes` (first ambiguous)
3. Type: `okay` (second ambiguous)
4. **Expected**: "I didn't quite get that. Please say 'continue previous', 'start new', or 'no'"

#### Test 4: Direct Clear Responses
1. Type: `help me code`
2. Try each:
   - `continue` → "Continuing previous session..."
   - `start new` → "Starting new session..."
   - `no` → "Session declined"
   - `purple` → "I didn't quite get that..."

### Checking State

The orchestrator now tracks:
- `pending_executor.is_initial_prompt`: true on first ask, false after re-prompt
- `pending_executor.session_action`: Set when user makes clear choice
- `last_completed_session_id`: Saved when session completes (for Phase 3)

### Debug Output
Run with debug logging:
```bash
RUST_LOG=orchestrator=debug ./target/debug/orchestrator
```

Look for:
- "Routing command..."
- "Handle confirmation response"
- "Would you like to continue..."
- Session action decisions

## Success Criteria

✅ "yes" alone triggers re-prompt asking for clarification
✅ Re-prompt clearly asks "continue previous or start new"
✅ Second ambiguous response treated as unintelligible
✅ Clear responses go directly to appropriate action
✅ State properly tracks initial vs re-prompt
✅ Mobile receives speak messages for re-prompts

## Next Phase Preview

Phase 3 will:
- Actually use `--resume <session_id>` for Continue
- Generate fresh session ID for New
- Load last_completed_session_id from disk