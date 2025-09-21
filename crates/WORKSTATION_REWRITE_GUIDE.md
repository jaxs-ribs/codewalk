# Workstation Rewrite Guide

## ⚠️ IMPORTANT: Read This First

You are about to rewrite the workstation orchestrator from scratch. The old code has served its purpose as a learning prototype, but contains significant technical debt. This guide will help you build it right.

**Golden Rule**: Build from the SPECS, not from the old code. If you need to check something, check the spec documents, NOT the legacy implementation.

## 📚 Required Reading (In Order)

1. **[FROZEN_CONTRACTS.md](./FROZEN_CONTRACTS.md)** - What CANNOT change
   - Read this first to understand your constraints
   - Mobile interface is frozen and must work unchanged
   - External dependencies we must support

2. **[MOBILE_INTERFACE_SPEC.md](./MOBILE_INTERFACE_SPEC.md)** - The frozen mobile protocol
   - This is your most critical constraint
   - Every message shape must match exactly
   - Test against this continuously

3. **[BEHAVIOR_SPEC.md](./BEHAVIOR_SPEC.md)** - What the system does
   - Functional requirements
   - User-visible behaviors
   - No implementation details

4. **[ARCHITECTURE_SPEC.md](./ARCHITECTURE_SPEC.md)** - How to build it right
   - Clean architecture design
   - State machine specification
   - Implementation strategy

## 🎯 Project Goals

### Immediate Goal
Build a clean execution-mode orchestrator that:
- Receives commands (voice/text) from mobile and TUI
- Routes commands via LLM to determine action
- Manages Claude/Devin executor sessions
- Maintains backward compatibility with mobile app

### Future Vision
Enable the full lifecycle: **Speccing → Executing → Inspecting**
- **Speccing**: Build configuration trees and plan phases with Socratic agent
- **Executing**: Current focus - run phased work with executors
- **Inspecting**: Verify and demonstrate completed work

## 🏗️ Recommended Project Structure

```
workstation/                    # New clean project
├── Cargo.toml                 # Workspace root
├── crates/
│   ├── workstation-core/      # Core state machine & logic
│   │   ├── src/
│   │   │   ├── state.rs       # State machine
│   │   │   ├── events.rs      # Event types
│   │   │   ├── effects.rs     # Effect system
│   │   │   ├── session.rs     # Session management
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   ├── workstation-protocol/  # Protocol types (frozen v1)
│   │   ├── src/
│   │   │   └── lib.rs         # Message types
│   │   └── Cargo.toml
│   │
│   ├── workstation-adapters/  # External integrations
│   │   ├── src/
│   │   │   ├── router.rs      # LLM router adapter
│   │   │   ├── executor.rs    # Claude/Devin adapter
│   │   │   ├── stt.rs         # Speech-to-text adapter
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   ├── workstation-transport/ # Transport layer
│   │   ├── src/
│   │   │   ├── relay.rs       # WebSocket relay client
│   │   │   ├── bridge.rs      # Protocol bridge
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   └── workstation-tui/       # TUI frontend (thin view)
│       ├── src/
│       │   ├── main.rs
│       │   ├── ui.rs          # Display only
│       │   └── input.rs       # Input handling
│       └── Cargo.toml
│
└── legacy/                     # Old code for reference ONLY
    └── (archived old code)
```

## 🚀 Implementation Plan

### Phase 1: Core State Machine (No Dependencies)
```rust
// Start here - pure business logic
enum WorkstationState {
    Idle,
    Executing(ExecutionState),
    // Future: Speccing, Inspecting
}
```
- Implement state transitions
- Build effect system
- Add comprehensive tests
- NO external dependencies yet

### Phase 2: Protocol & Transport
- Implement frozen protocol types
- Build protocol bridge (events ↔ messages)
- Add relay client for mobile
- Test mobile compatibility early

### Phase 3: Adapters
- Router adapter (LLM integration)
- Executor adapter (Claude)
- STT adapter (Groq Whisper)
- Use interfaces, allow mocking

### Phase 4: Minimal TUI
- Display state and logs
- Handle input
- NO business logic
- Just a thin view layer

### Phase 5: Integration & Testing
- End-to-end flows
- Mobile app testing
- Session persistence
- Error scenarios

## ✅ Implementation Checklist

### Core Functionality
- [ ] State machine with explicit transitions
- [ ] Event system with type safety
- [ ] Effect runtime for side effects
- [ ] Session management
- [ ] Logging and persistence

### Mobile Compatibility
- [ ] All protocol messages match spec exactly
- [ ] Relay WebSocket connection works
- [ ] STT request/response handling
- [ ] Log fetching works
- [ ] Confirmation flow works

### External Integrations
- [ ] Claude executor launches and streams output
- [ ] Router makes correct decisions
- [ ] STT processes audio correctly
- [ ] Summarizer generates good summaries

### User Experience
- [ ] Commands route correctly
- [ ] Status queries return meaningful info
- [ ] Confirmations work properly
- [ ] Errors are handled gracefully
- [ ] Sessions persist and can be resumed

## 🧪 Testing Strategy

### Unit Tests (Core)
```rust
#[test]
fn test_idle_to_executing_transition() {
    // Test pure state logic
}
```

### Integration Tests (Adapters)
```rust
#[test]
async fn test_claude_executor_lifecycle() {
    // Test with real/mock executor
}
```

### Contract Tests (Protocol)
```rust
#[test]
fn test_mobile_message_compatibility() {
    // Verify against frozen spec
}
```

### End-to-End Tests
```rust
#[test]
async fn test_voice_command_to_execution() {
    // Full flow with mocks
}
```

## 🚫 Common Pitfalls to Avoid

1. **Don't mix concerns** - State logic shouldn't know about protocols
2. **Don't poll unnecessarily** - Use events and async/await properly
3. **Don't leak abstractions** - Ports should hide implementation details
4. **Don't forget mobile** - Test compatibility continuously
5. **Don't copy old patterns** - Build from specs, not old code

## 📝 Key Design Decisions

### Why Hierarchical State Machine?
- Natural fit for Speccing → Executing → Inspecting
- Clear state boundaries
- Easier to reason about
- Extensible for future modes

### Why Effect System?
- Separates pure logic from side effects
- Makes testing easier
- Enables replay and debugging
- Clean async boundaries

### Why Protocol Bridge?
- Core stays protocol-agnostic
- Easy to add new frontends
- Backward compatibility isolated
- Clear transformation layer

## 🔍 When You Get Stuck

1. **Check the specs** - They define the requirements
2. **Check frozen contracts** - These are your constraints
3. **Check the behavior spec** - What should it do?
4. **Don't check old code** - It will mislead you

## 📈 Success Metrics

- **Clean**: Each component has single responsibility
- **Testable**: >90% test coverage on core logic
- **Fast**: No blocking operations in hot paths
- **Compatible**: Mobile app works unchanged
- **Extensible**: Adding speccing/inspecting modes is straightforward

## 🎬 Getting Started

1. Create new workspace structure
2. Copy protocol types (frozen v1) to `workstation-protocol`
3. Start with state machine in `workstation-core`
4. Build outward from the core
5. Test mobile compatibility early and often

Remember: The goal is not to port the old code, but to build a clean system that provides the same behavior through better architecture.

---

*This guide is a living document. Update it as you make design decisions and learn from the implementation.*