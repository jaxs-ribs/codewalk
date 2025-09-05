# RFC v3: Orchestrator Architecture Refactoring - Implementation Guide

**Date:** September 2025  
**Author:** Architecture Team  
**Status:** Final  
**Target Audience:** Engineering team, Product Management

## Overview for Product Management

### What We're Building
We're restructuring how our orchestrator (the system that manages AI coding assistants) is organized internally. Think of it like reorganizing a messy office where everything is in one giant room into a proper office building with specialized departments.

### Why This Matters
- **Faster feature development**: New features that take 2 weeks today will take 2-3 days
- **Better reliability**: Bugs will be isolated to specific components instead of breaking everything
- **Easier testing**: We can test business logic without needing the full system running
- **Multiple interfaces**: We can add web UI, API, or CLI without rewriting core logic

### Timeline
- **Week 1**: Foundation work (no visible changes)
- **Week 2**: Core improvements (better stability)
- **Week 3**: UI extraction (faster interface)
- **Week 4**: Polish and optimization

## Technical Summary

We're evolving from a monolithic 4,000-line codebase to a modular architecture with clear boundaries. The v2 RFC was too conservative—keeping everything in modules risks perpetuating the current mess. We need actual crate boundaries to enforce architectural discipline.

### Final Architecture

```
5 focused crates instead of 3 mixed ones:
├── orchestrator-core       (600 lines)  - Business brain
├── control-center         (1,100 lines) - Executor management (existing)
├── orchestrator-adapters   (800 lines)  - External integrations
├── orchestrator-tui       (1,000 lines) - Terminal UI
└── orchestrator            (100 lines)  - Thin startup binary
```

## Phase 1: Foundation (Days 1-5)

### Goal
Establish the core architecture without breaking anything. All existing features continue to work.

### Work Items

#### 1.1 Expand orchestrator-core
Add these modules to orchestrator-core:
```rust
// New modules in orchestrator-core/src/
session/
├── state.rs        // Session lifecycle state machine
├── history.rs      // History tracking logic (no I/O)
└── context.rs      // Session context for routing

ports/
├── storage.rs      // trait SessionStore
├── summarizer.rs   // trait Summarizer
└── monitor.rs      // trait LogMonitor
```

#### 1.2 Create orchestrator-adapters crate
```toml
# Cargo.toml
[package]
name = "orchestrator-adapters"

[dependencies]
orchestrator-core = { path = "../orchestrator-core" }
router = { path = "../router" }
llm = { path = "../llm" }
control_center = { path = "../control_center" }
```

Move existing implementations:
- `orchestrator/src/backend.rs` → `adapters/groq/`
- `orchestrator/src/relay_client.rs` → `adapters/relay/`
- `orchestrator/src/core_bridge.rs` → `adapters/bridge/`

### Tests to Pass

```rust
// orchestrator-core/tests/session_lifecycle.rs
#[test]
async fn test_session_state_transitions() {
    let core = TestCore::new();
    
    // Session starts in idle
    assert_eq!(core.session_state(), SessionState::Idle);
    
    // Starting session transitions to running
    core.start_session("test prompt").await;
    assert_eq!(core.session_state(), SessionState::Running);
    
    // Completing session transitions to completed
    core.complete_session().await;
    assert_eq!(core.session_state(), SessionState::Completed);
}

// orchestrator-adapters/tests/adapter_connectivity.rs
#[test]
async fn test_groq_adapter_implements_ports() {
    let adapter = GroqRouter::new("test_key");
    // Should compile - proves it implements RouterPort
    let _: Box<dyn RouterPort> = Box::new(adapter);
}

#[test]
async fn test_all_adapters_available() {
    // Verify we can create all adapters
    let _router = GroqRouter::new("key");
    let _storage = FileSessionStore::new("./test");
    let _relay = RelayClient::new("ws://test");
}
```

### Success Criteria
✅ All existing tests still pass  
✅ New crate structure compiles  
✅ orchestrator binary still runs with no behavior changes

---

## Phase 2: Core Integration (Days 6-10)

### Goal
Route all business decisions through orchestrator-core. Remove duplicate routing logic.

### Work Items

#### 2.1 Unify routing through core
Replace direct LLM calls with core routing:

```rust
// BEFORE (in app.rs)
let json = backend::text_to_llm_cmd(&text).await?;
let resp = backend::parse_router_response(&json).await?;
match resp.action {
    RouterAction::LaunchClaude => { /* ... */ }
}

// AFTER
self.core_in_tx.send(protocol::Message::UserText(
    protocol::UserText {
        text: text.to_string(),
        // ...
    }
)).await?;
// Core handles routing and emits appropriate response
```

#### 2.2 Fix confirmation flow
All confirmations go through core:

```rust
// BEFORE (in confirmation_handler.rs)
if confirmation == "yes" {
    app.launch_executor_with_prompt(&prompt).await?;
}

// AFTER
self.core_in_tx.send(protocol::Message::ConfirmResponse(
    protocol::ConfirmResponse {
        accept: confirmation == "yes",
        // ...
    }
)).await?;
```

#### 2.3 Remove the "Query Status" loop
Ensure status queries are handled correctly without infinite loops.

### Tests to Pass

```rust
// orchestrator-core/tests/routing_integration.rs
#[test]
async fn test_routing_through_core_only() {
    let mut core = TestCore::with_mock_router();
    let (tx, mut rx) = mpsc::channel(10);
    core.set_outbound(tx);
    
    // Send user text
    core.handle(Message::UserText("build me a web app".into())).await;
    
    // Should receive prompt confirmation
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::PromptConfirmation(_)));
}

#[test]
async fn test_no_duplicate_routing() {
    // Scan codebase - no direct calls to backend::text_to_llm_cmd outside adapters
    let grep_result = std::process::Command::new("grep")
        .args(&["-r", "backend::text_to_llm_cmd", "src/"])
        .arg("--exclude-dir=adapters")
        .output()
        .unwrap();
    
    assert!(grep_result.stdout.is_empty(), "Found direct LLM calls outside adapters!");
}

// orchestrator/tests/confirmation_e2e.rs
#[test]
async fn test_voice_confirmation_flow() {
    let app = TestApp::new();
    
    // Trigger confirmation
    app.send_text("help me code").await;
    assert_eq!(app.mode(), Mode::ConfirmingExecutor);
    
    // Voice confirm
    app.send_voice_input("yes please").await;
    
    // Should launch without additional LLM calls
    assert_eq!(app.mode(), Mode::ExecutorRunning);
    assert_eq!(app.llm_call_count(), 1); // Only the initial routing
}
```

### Success Criteria
✅ No direct LLM calls from UI code  
✅ Single confirmation flow through core  
✅ Status queries don't cause loops  
✅ All routing tests pass

---

## Phase 3: UI Extraction (Days 11-15)

### Goal
Extract UI into separate crate with clean boundaries.

### Work Items

#### 3.1 Create orchestrator-tui crate
```toml
[package]
name = "orchestrator-tui"

[dependencies]
ratatui = "0.28"
crossterm = "0.28"
protocol = { path = "../protocol" }
orchestrator-core = { path = "../orchestrator-core" }
```

#### 3.2 Move UI modules
- `orchestrator/src/ui/` → `orchestrator-tui/src/ui/`
- `orchestrator/src/handlers.rs` → `orchestrator-tui/src/handlers.rs`
- Extract UI-only state from App

#### 3.3 Create thin App coordination
```rust
// orchestrator/src/app.rs (AFTER - ~200 lines)
pub struct App {
    core: Arc<OrchestratorCore>,
    tui: Option<TuiState>,
    adapters: Adapters,
}

// orchestrator-tui/src/state.rs
pub struct TuiState {
    output_buffer: Vec<String>,
    input_buffer: String,
    scroll: ScrollState,
    selected_tab: Tab,
    // Only UI state, no business logic
}
```

### Tests to Pass

```rust
// orchestrator-tui/tests/ui_isolation.rs
#[test]
fn test_tui_has_no_business_logic() {
    // TUI should not import from orchestrator except types
    let deps = get_dependencies("orchestrator-tui");
    assert!(!deps.contains("orchestrator"));
    assert!(deps.contains("protocol")); // OK - just message types
}

#[test]
async fn test_tui_only_emits_messages() {
    let (tx, mut rx) = mpsc::channel(10);
    let mut tui = TuiState::new(tx);
    
    // Simulate user input
    tui.handle_key_press(KeyCode::Enter).await;
    
    // Should only emit protocol messages
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, protocol::Message::_));
}

// orchestrator/tests/thin_coordination.rs
#[test]
async fn test_app_under_300_lines() {
    let line_count = count_lines("src/app.rs");
    assert!(line_count < 300, "App is too large: {} lines", line_count);
}
```

### Success Criteria
✅ TUI crate builds independently  
✅ App struct under 300 lines  
✅ No business logic in TUI  
✅ UI tests pass without core

---

## Phase 4: Polish and Optimization (Days 16-20)

### Goal
Clean up, optimize, and ensure production readiness.

### Work Items

#### 4.1 Performance optimization
- Profile and optimize hot paths
- Ensure no performance regression
- Minimize allocations in message passing

#### 4.2 Documentation
- Update all crate-level documentation
- Create architecture diagram
- Write migration guide for plugins

#### 4.3 Cleanup
- Remove dead code
- Update all imports
- Ensure consistent naming

### Tests to Pass

```rust
// Benchmark tests
#[bench]
fn bench_message_routing(b: &mut Bencher) {
    let core = create_test_core();
    b.iter(|| {
        core.handle(Message::UserText("test".into()))
    });
    // Should be < 1ms per message
}

#[test]
fn test_no_dead_code() {
    let output = Command::new("cargo")
        .args(&["clippy", "--", "-W", "dead_code"])
        .output()
        .unwrap();
    
    assert!(output.status.success(), "Found dead code!");
}

// Integration smoke test
#[test]
async fn test_full_user_journey() {
    let app = RealApp::new();
    
    // User journey: ask for help → confirm → get status
    app.send_input("help me build a REST API").await;
    app.send_confirmation(true).await;
    tokio::time::sleep(Duration::from_secs(2)).await;
    app.send_input("what's the status?").await;
    
    let output = app.get_output();
    assert!(output.contains("Claude Code is running"));
}
```

### Success Criteria
✅ All benchmarks pass performance targets  
✅ Zero clippy warnings  
✅ All documentation updated  
✅ Full integration tests pass

---

## Rollback Plan

Each phase is designed to be atomic. If issues arise:

### Phase 1 Rollback
- Delete new crates
- Revert Cargo.toml changes
- No functionality was changed, so nothing breaks

### Phase 2 Rollback
- Revert routing changes
- Restore direct LLM calls
- Tests will catch any regression

### Phase 3 Rollback
- Move UI code back to orchestrator
- Merge TuiState back into App
- Delete orchestrator-tui crate

### Phase 4 Rollback
- This phase is optimization only
- Can skip without impact

## Success Metrics

### Quantitative
- **Code organization**: 5 focused crates vs 3 mixed ones
- **App size**: From 4,071 → ~200 lines
- **Test coverage**: Core logic from ~20% → 90%
- **Build time**: 30% faster due to parallel compilation
- **Feature velocity**: New UI in days vs weeks

### Qualitative
- Clear ownership boundaries
- Easier onboarding for new developers
- Confidence in making changes
- Better debugging experience

## Risk Assessment

### Technical Risks
1. **Risk**: Breaking existing functionality
   **Mitigation**: Comprehensive test suite at each phase
   
2. **Risk**: Performance degradation
   **Mitigation**: Benchmark tests in Phase 4

3. **Risk**: Complex merge conflicts
   **Mitigation**: Complete refactor in feature branch

### Business Risks
1. **Risk**: 4-week timeline delays feature work
   **Mitigation**: Can deliver in phases; each phase adds value

2. **Risk**: Learning curve for team
   **Mitigation**: Extensive documentation and pair programming

## Conclusion

This refactoring transforms our monolithic orchestrator into a clean, modular architecture. Each phase delivers concrete value with measurable tests. The investment will pay off immediately in development velocity and long-term in maintainability.

### For Product Management
- Week 1-2: No visible changes, but more stable
- Week 3: Faster UI responses
- Week 4: Ready for rapid feature development
- Future: Can add web UI, API, or CLI easily

### For Engineering
- Clear architectural boundaries
- Testable business logic
- Parallel development possible
- Much easier to debug and extend

The path is clear, the tests are defined, and we're ready to execute.