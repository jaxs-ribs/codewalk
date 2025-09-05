# Phase 1 Refactoring Plan: Execution-Only State Machine

## Goal
Refactor the current orchestrator to cleanly separate core state management from UI concerns, while maintaining all existing functionality. Focus only on execution mode initially, but architect for future speccing and inspection modes.

## Current Problems

1. **Mixed Concerns**: TUI state (`Mode` enum) conflates UI states with orchestrator states
2. **Scattered Logic**: State management spread across `app.rs`, `handlers.rs`, and `core_bridge.rs`
3. **Implicit States**: Session management happens through various flags rather than explicit states
4. **Tight Coupling**: TUI drives orchestrator rather than responding to it

## Proposed Architecture

### Core State Machine (in orchestrator_core)

```rust
// Core work states - this is the real state machine
enum WorkstationState {
    Idle,                          // No active work
    Executing(ExecutionState),     // Work in progress
    // Future: Speccing, Inspecting
}

enum ExecutionState {
    AwaitingConfirmation {
        prompt: String,
        confirmation_id: String,
    },
    Running {
        session_id: String,
        executor_type: String,
    },
    // Future: Interrupted, PhaseComplete
}
```

### Refactoring Steps

## Step 1: Extract Core State Machine
**Location**: `orchestrator_core/src/state.rs` (new file)

- Move state definitions from `types.rs` to core
- Create state transition functions with explicit rules
- Add state change events that frontends can observe

```rust
impl WorkstationState {
    fn transition(&mut self, event: StateEvent) -> Result<()> {
        match (self, event) {
            (Idle, StartExecution(prompt)) => {
                *self = Executing(AwaitingConfirmation { ... });
            }
            // ... explicit transition rules
        }
    }
}
```

## Step 2: Simplify TUI Mode
**Location**: `crates/orchestrator/src/types.rs`

Reduce to pure UI concerns:
```rust
enum TUIMode {
    Normal,           // Regular display
    Recording,        // Voice input active
    ShowingError,     // Error dialog visible
    // Remove: PlanPending, Executing, ConfirmingExecutor
}
```

## Step 3: Create State Synchronization
**Location**: `crates/orchestrator/src/app.rs`

- TUI observes core state changes
- Updates UI mode based on core state
- No business logic in TUI

```rust
impl App {
    fn sync_with_core_state(&mut self, core_state: &WorkstationState) {
        // Update UI elements based on core state
        // But don't make decisions about state transitions
    }
}
```

## Step 4: Centralize Message Flow
**Location**: `orchestrator_core/src/orchestrator.rs`

All messages flow through core:
```
User Input → Core → State Machine → State Change → Notify Frontends
                 ↓
             Router → Executor
```

## Step 5: Clean Up Session Management
**Location**: `orchestrator_core/src/session.rs` (new file)

- Extract session tracking from `app.rs`
- Create proper `Session` struct with lifecycle
- Move session persistence to core

## Implementation Order

### Phase 1A: Core Extraction (Non-breaking)
1. Create new state module in core
2. Add parallel state tracking (keep old Mode for now)
3. Add state change events
4. Test with existing TUI

### Phase 1B: TUI Simplification
1. Migrate handlers to use core state
2. Remove business logic from TUI
3. Simplify Mode enum to UI-only
4. Update display logic

### Phase 1C: Session Cleanup
1. Extract session management to core
2. Unify session ID generation
3. Move persistence logic
4. Clean up app.rs

## Validation Criteria

After refactoring, we should have:

1. **Clean Separation**: 
   - Core knows nothing about TUI
   - TUI has no business logic
   
2. **Maintained Functionality**:
   - Voice input still works
   - Executor launching unchanged
   - Session tracking preserved
   - Mobile relay functional

3. **Better Testability**:
   - Can test state machine without UI
   - Can test UI without core logic
   - Clear state transition rules

4. **Future Ready**:
   - Easy to add speccing mode
   - Easy to add inspection mode
   - Easy to add new frontends

## Migration Strategy

1. **Parallel Implementation**: Build new state machine alongside existing code
2. **Feature Flag**: Use feature flag to switch between old and new
3. **Incremental Migration**: Migrate one component at a time
4. **Test Coverage**: Add tests for state transitions before refactoring
5. **Documentation**: Document state machine formally

## Code Locations to Modify

### High Priority (Core Logic)
- `orchestrator_core/src/lib.rs` - Add state module
- `orchestrator_core/src/state.rs` - New state machine
- `orchestrator_core/src/session.rs` - New session management

### Medium Priority (TUI Updates)
- `crates/orchestrator/src/types.rs` - Simplify Mode enum
- `crates/orchestrator/src/app.rs` - Remove business logic
- `crates/orchestrator/src/handlers.rs` - Use core state

### Low Priority (Cleanup)
- `crates/orchestrator/src/confirmation_handler.rs` - Might become obsolete
- `crates/orchestrator/src/core_bridge.rs` - Simplify adapter pattern

## Benefits

1. **Immediate**: Cleaner code, better separation
2. **Short-term**: Easier to add features, better testing
3. **Long-term**: Ready for speccing/inspection modes

## Risks and Mitigations

**Risk**: Breaking existing functionality
**Mitigation**: Parallel implementation with feature flag

**Risk**: Complex migration
**Mitigation**: Incremental changes with tests

**Risk**: Performance regression
**Mitigation**: State machine is simpler, should be faster

## Success Metrics

- All existing tests pass
- State transitions are explicit and logged
- TUI code reduced by ~30%
- Core can run headless with full functionality
- Adding a new frontend requires <100 lines of code