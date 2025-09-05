# RFC: Orchestrator Architecture Refactoring

**Date:** September 2025  
**Author:** Architecture Team  
**Status:** Draft  

## Executive Summary

This RFC proposes a comprehensive refactoring of the orchestrator system to address critical architectural issues: a 4,000+ line monolithic crate mixing UI, business logic, and infrastructure concerns. The refactoring will expand `orchestrator-core` to be the true domain core, properly decompose `control-center`, and establish clear architectural boundaries following hexagonal architecture principles.

## Problem Statement

### Current Architecture Issues

1. **The Monolith Problem**: The main `orchestrator` crate (4,071 lines) is a god object containing:
   - Terminal UI components and event handling
   - Session management and history tracking
   - Direct integration with external services (Groq, STT, WebSocket relay)
   - Business logic mixed with infrastructure code
   - 30+ fields in the main `App` struct managing everything

2. **Underutilized Core**: `orchestrator-core` (418 lines) implements clean hexagonal architecture but only handles:
   - Message routing
   - Confirmation flow
   - Basic protocol handling
   
   It should be the domain brain but currently handles only a fraction of business logic.

3. **Confused Boundaries**: `control-center` (1,093 lines) conflates three distinct responsibilities:
   - Process lifecycle management (spawning, killing executors)
   - Log parsing and analysis
   - Session coordination

### Impact on Development

- **Testing Nightmare**: Cannot test business logic without mocking UI, files, and network calls
- **Feature Addition Complexity**: Adding a new UI requires understanding all 4,000 lines
- **Tight Coupling**: Changing log storage means modifying core business logic
- **Maintenance Burden**: Bug fixes require navigating through mixed concerns

## Proposed Solution

### Core Principle: Hexagonal Architecture Everywhere

The refactoring follows hexagonal architecture (ports and adapters) at every level:
- **Domain Core**: Pure business logic with zero external dependencies
- **Ports**: Interfaces the domain defines for its needs
- **Adapters**: Implementations connecting to external systems
- **Clear Dependencies**: Flow from outside → adapters → ports → domain

### New Crate Structure

```
codewalk/
├── orchestrator-core/      # Expanded domain core (the brain)
├── executor-toolkit/       # Process management and log processing
├── orchestrator-adapters/  # All external integrations
├── orchestrator-tui/       # Terminal UI only
└── orchestrator/          # Thin binary for wiring
```

## Detailed Design

### 1. orchestrator-core: The Domain Brain

**Purpose**: Own ALL business logic and state machines. Zero external dependencies.

**Current Responsibilities** (keep):
- Message protocol handling
- Command routing decisions
- Confirmation workflows

**New Responsibilities** (add):
- Session lifecycle management
- Session history tracking
- Artifact management
- Summarization orchestration (not the AI call, but the logic)

**Structure**:
```rust
orchestrator-core/
├── routing/
│   ├── classifier.rs    // Command intent classification
│   └── decisions.rs     // Routing state machine
├── confirmation/
│   └── flow.rs          // Confirmation state machine
├── session/
│   ├── lifecycle.rs     // Session state: Starting → Running → Completed
│   ├── history.rs       // History management logic
│   └── artifacts.rs     // Artifact tracking logic
├── summarization/
│   └── orchestrator.rs  // When/what to summarize (not how)
├── events/
│   └── domain.rs        // Domain events
└── ports/
    ├── routing.rs       // trait RouterPort (existing)
    ├── executor.rs      // trait ExecutorPort (existing)
    ├── storage.rs       // trait SessionStore (new)
    ├── monitor.rs       // trait LogMonitor (new)
    └── summarizer.rs    // trait Summarizer (new)
```

**Example Port Definition**:
```rust
// ports/storage.rs
#[async_trait]
pub trait SessionStore: Send + Sync {
    async fn save_session(&self, session: &Session) -> Result<()>;
    async fn load_session(&self, id: &SessionId) -> Result<Session>;
    async fn list_sessions(&self, filter: SessionFilter) -> Result<Vec<SessionSummary>>;
}

// The core doesn't know if this is files, Redis, or PostgreSQL
```

### 2. executor-toolkit: Process and Log Management

**Purpose**: Handle the mechanical aspects of running and monitoring external executors.

**Formed by splitting** `control-center` into:

**Structure**:
```rust
executor-toolkit/
├── runtime/
│   ├── process.rs       // Process spawning, I/O handling
│   ├── claude.rs        // Claude-specific launch logic
│   └── traits.rs        // trait ExecutorSession
├── logs/
│   ├── parser/
│   │   ├── claude.rs    // Parse Claude Code JSON logs
│   │   └── generic.rs   // Fallback parser
│   ├── monitor.rs       // File watching
│   └── filter.rs        // Log extraction for summaries
└── controller.rs        // Coordinates runtime + logs
```

**Key Trait**:
```rust
#[async_trait]
pub trait ExecutorSession: Send {
    async fn launch(prompt: &str, config: Config) -> Result<Self>;
    async fn read_output(&mut self) -> Result<Option<Output>>;
    fn is_running(&self) -> bool;
    async fn terminate(&mut self) -> Result<()>;
}
```

### 3. orchestrator-adapters: External Integrations

**Purpose**: Implement all ports defined by orchestrator-core using actual external services.

**Structure**:
```rust
orchestrator-adapters/
├── groq/
│   ├── router.rs        // implements RouterPort using Groq LLM
│   └── summarizer.rs    // implements Summarizer using Groq
├── storage/
│   ├── file.rs          // implements SessionStore using filesystem
│   └── redis.rs         // future: Redis implementation
├── stt/
│   └── groq_stt.rs      // Speech-to-text service
├── relay/
│   └── websocket.rs     // WebSocket relay client
└── monitoring/
    └── file_monitor.rs   // implements LogMonitor
```

**Example Adapter**:
```rust
// storage/file.rs
pub struct FileSessionStore {
    base_dir: PathBuf,
}

#[async_trait]
impl SessionStore for FileSessionStore {
    async fn save_session(&self, session: &Session) -> Result<()> {
        let path = self.base_dir.join(format!("{}.json", session.id));
        let json = serde_json::to_string_pretty(session)?;
        tokio::fs::write(path, json).await?;
        Ok(())
    }
    // ... other methods
}
```

### 4. orchestrator-tui: Pure Presentation Layer

**Purpose**: Terminal UI only. No business logic.

**Structure**:
```rust
orchestrator-tui/
├── state.rs         // UI state (scroll positions, input buffer)
├── ui/
│   ├── layout.rs    // Screen layout
│   ├── components/  // UI components
│   └── styles.rs    // Terminal styles
├── input.rs         // Keyboard event handling
└── app.rs           // TUI application loop
```

**Clean Separation**:
```rust
// Before: Mixed concerns in App
pub struct App {
    output: Vec<String>,           // UI
    session_logs: Vec<Log>,        // Domain
    scroll: ScrollState,           // UI
    active_executor: Executor,    // Domain
    input_buffer: String,         // UI
    relay_client: WebSocket,      // Infrastructure
    // ... 30+ mixed fields
}

// After: Pure UI state
pub struct TuiState {
    output_buffer: Vec<String>,
    input_buffer: String,
    scroll: ScrollState,
    selected_tab: Tab,
    // Only UI concerns
}
```

### 5. orchestrator: Thin Binary

**Purpose**: Wire everything together and start the application.

**Structure** (~100 lines total):
```rust
// src/main.rs
#[tokio::main]
async fn main() -> Result<()> {
    // 1. Load configuration
    let config = Config::from_env()?;
    
    // 2. Create adapters
    let storage = FileSessionStore::new("./sessions");
    let router = GroqRouter::new(config.groq_api_key);
    let summarizer = GroqSummarizer::new(config.groq_api_key);
    let monitor = FileLogMonitor::new();
    
    // 3. Create executor toolkit
    let executor = ExecutorController::new();
    
    // 4. Create core with all dependencies
    let core = OrchestratorCore::builder()
        .with_storage(storage)
        .with_router(router)
        .with_executor(executor)
        .with_monitor(monitor)
        .with_summarizer(summarizer)
        .build();
    
    // 5. Start UI or headless mode
    if config.tui_enabled {
        let tui = TuiApp::new(core);
        tui.run().await?;
    } else {
        let headless = HeadlessApp::new(core);
        headless.run().await?;
    }
    
    Ok(())
}
```

## Migration Strategy

### Phase 1: Extract Without Breaking (Week 1)

**Goal**: Create new crate structure without changing functionality.

1. **Create orchestrator-adapters**:
   - Move `backend.rs` → `adapters/groq/`
   - Move `relay_client.rs` → `adapters/relay/`
   - Keep existing interfaces

2. **Expand orchestrator-core**:
   - Add session management modules
   - Define new ports
   - Keep backward compatibility

3. **Split control-center**:
   - Create executor-toolkit crate
   - Move process management → `executor-toolkit/runtime/`
   - Move log parsing → `executor-toolkit/logs/`
   - Leave thin coordination layer

### Phase 2: Rewire Dependencies (Week 2)

**Goal**: Make orchestrator use new crates.

1. **Update orchestrator to use adapters**:
   ```rust
   // Before
   use crate::backend;
   
   // After  
   use orchestrator_adapters::groq::GroqRouter;
   ```

2. **Move session logic to core**:
   - Extract from `App` struct
   - Implement via ports

3. **Create TUI crate**:
   - Move all UI modules
   - Extract UI state from App

### Phase 3: Clean Up (Days 3-4)

**Goal**: Remove duplication and optimize.

1. Delete moved code from orchestrator
2. Simplify App struct to coordination only
3. Update tests to use new structure
4. Update documentation

## Testing Strategy

### Unit Testing Becomes Trivial

```rust
// orchestrator-core tests: Pure logic, no mocks needed
#[test]
async fn test_session_lifecycle() {
    let store = InMemoryStore::new();  // Test implementation
    let core = OrchestratorCore::test_config(store);
    
    let session = core.start_session("test prompt").await;
    assert_eq!(session.state, SessionState::Running);
    
    core.complete_session(session.id).await;
    assert_eq!(session.state, SessionState::Completed);
}
```

### Integration Testing

```rust
// Test real adapters in isolation
#[test]
async fn test_groq_router() {
    let router = GroqRouter::new(test_api_key());
    let result = router.route("build me a web app").await?;
    assert_eq!(result.action, RouteAction::LaunchClaude);
}
```

## Benefits

### Immediate Benefits

1. **Testability**: Can test business logic without external dependencies
2. **Clarity**: Each crate has one clear purpose
3. **Maintainability**: Bugs are isolated to specific domains
4. **Parallel Development**: Teams can work on different crates independently

### Future Benefits

1. **Multiple UIs**: Add web UI, CLI, or API without touching core
2. **Storage Options**: Switch from files to database with one adapter change
3. **Executor Variety**: Add Devin, Codex, or custom executors easily
4. **Monitoring**: Plug in different monitoring solutions

## Risks and Mitigations

### Risk 1: Over-Engineering
**Mitigation**: Keep minimum viable crates (5 instead of 10+). Can always split more later.

### Risk 2: Breaking Changes
**Mitigation**: Phase 1 adds new structure alongside old. Only remove old code after new is proven.

### Risk 3: Performance Impact
**Mitigation**: Trait objects have minimal overhead. Async boundaries already exist.

## Success Metrics

1. **Code Reduction**: Orchestrator crate from 4,071 → ~200 lines
2. **Test Coverage**: Core logic coverage from ~20% → 90%
3. **Build Time**: Parallel compilation of independent crates
4. **Feature Velocity**: Adding new UI should take days, not weeks

## Timeline

- **Week 1**: Phase 1 (Extract without breaking)
- **Week 2**: Phase 2 (Rewire dependencies)
- **Days 15-17**: Phase 3 (Clean up)
- **Days 18-21**: Testing and documentation

Total: **3 weeks** for complete refactor

## Conclusion

This refactoring transforms a 4,000-line monolith into a clean, modular architecture where:
- Business logic lives in one place (orchestrator-core)
- Each crate has a single responsibility
- Dependencies flow in one direction
- Testing becomes trivial
- Future changes become local

The investment of 3 weeks will pay dividends in maintainability, testability, and development velocity.