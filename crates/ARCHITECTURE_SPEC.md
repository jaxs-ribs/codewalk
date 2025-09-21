# Clean Architecture Specification

This document describes the target architecture for the workstation rewrite, incorporating the vision of Speccing → Executing → Inspecting while maintaining backward compatibility with frozen interfaces.

## Design Principles

1. **State Machine First** - All behavior flows from explicit state transitions
2. **Clean Layers** - Strict separation between core logic, adapters, and UI
3. **Event-Driven** - State changes and effects via events, not polling
4. **Protocol-Agnostic Core** - Core knows nothing about transport/serialization
5. **Extensible** - Easy to add new states, executors, and frontends

## Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Frontend Layer                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │   TUI    │  │  Mobile  │  │   Web    │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────┬───────────────────────────────┘
                          │ Protocol Messages
┌─────────────────────────┴───────────────────────────────┐
│                    Transport Layer                       │
│  ┌──────────────┐  ┌──────────────┐                    │
│  │ Relay Client │  │ Local Socket │                    │
│  └──────────────┘  └──────────────┘                    │
└─────────────────────────┬───────────────────────────────┘
                          │ Events
┌─────────────────────────┴───────────────────────────────┐
│                 Orchestrator Core                        │
│  ┌──────────────────────────────────────────────┐      │
│  │          Hierarchical State Machine          │      │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐    │      │
│  │  │ Speccing │ │Executing │ │Inspecting│    │      │
│  │  └──────────┘ └──────────┘ └──────────┘    │      │
│  └──────────────────────────────────────────────┘      │
│  ┌──────────────────────────────────────────────┐      │
│  │           Session Management                 │      │
│  └──────────────────────────────────────────────┘      │
│  ┌──────────────────────────────────────────────┐      │
│  │           Effect Handlers                    │      │
│  └──────────────────────────────────────────────┘      │
└─────────────────────────┬───────────────────────────────┘
                          │ Ports
┌─────────────────────────┴───────────────────────────────┐
│                    Adapter Layer                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  Router  │  │ Executor │  │    STT   │              │
│  │ (LLM)    │  │ (Claude) │  │ (Whisper)│              │
│  └──────────┘  └──────────┘  └──────────┘              │
└──────────────────────────────────────────────────────────┘
```

## Core State Machine

### Top-Level States

```rust
enum WorkstationState {
    Idle,
    Speccing(SpecState),
    Executing(ExecutionState),
    Inspecting(InspectionState),
}
```

### Speccing State (Future)

```rust
enum SpecState {
    BuildingConfiguration {
        tree: ConfigTree,
        agent: SpecAgent,
    },
    PlanningPhases {
        config: ConfigTree,
        phases: Vec<Phase>,
    },
}
```

### Executing State (Current Focus)

```rust
enum ExecutionState {
    RequestingConfirmation {
        id: ConfirmationId,
        request: ExecutorRequest,
    },
    Starting {
        request: ExecutorRequest,
    },
    Running {
        session: Session,
        executor: Box<dyn Executor>,
    },
    Interrupted {
        session: Session,
        reason: String,
    },
    Completing {
        session: Session,
        summary: String,
    },
}
```

### Inspecting State (Future)

```rust
enum InspectionState {
    Reviewing {
        session: Session,
        artifacts: Vec<Artifact>,
    },
    Demonstrating {
        session: Session,
        driver: DemoDriver,
    },
    Verifying {
        session: Session,
        verifier: Verifier,
    },
}
```

## Event System

### Event Types

```rust
enum Event {
    // Input events
    UserInput(Input),
    
    // State requests
    RequestExecution(ExecutorRequest),
    RequestSpeccing(SpecRequest),
    RequestInspection(InspectionRequest),
    
    // Confirmations
    ConfirmationReceived(ConfirmationId, bool),
    
    // Executor events
    ExecutorStarted(SessionId),
    ExecutorOutput(SessionId, Output),
    ExecutorCompleted(SessionId, Summary),
    ExecutorFailed(SessionId, Error),
    
    // System events
    Tick,
}
```

### Effect Types

```rust
enum Effect {
    // External calls
    StartExecutor(ExecutorRequest),
    StopExecutor(SessionId),
    RouteInput(String, Context),
    ProcessSTT(AudioData),
    
    // Notifications
    SendConfirmationRequest(ConfirmationRequest),
    SendStatus(Status),
    BroadcastStateChange(StateChange),
    
    // Persistence
    SaveSession(Session),
    SaveLogs(SessionId, Vec<Log>),
}
```

## Core Components

### 1. State Machine Core

```rust
struct StateMachine {
    state: WorkstationState,
    context: Context,
}

impl StateMachine {
    fn handle_event(&mut self, event: Event) -> Vec<Effect> {
        match (&self.state, event) {
            // Explicit state transitions
            // Return effects to be handled
        }
    }
}
```

### 2. Effect Runtime

```rust
struct EffectRuntime {
    handlers: HashMap<EffectType, Box<dyn EffectHandler>>,
}

impl EffectRuntime {
    async fn handle_effects(&self, effects: Vec<Effect>) {
        for effect in effects {
            self.dispatch(effect).await;
        }
    }
}
```

### 3. Session Manager

```rust
struct SessionManager {
    active: Option<Session>,
    history: Vec<Session>,
    storage: Box<dyn SessionStorage>,
}

struct Session {
    id: SessionId,
    phase: Phase,
    logs: Vec<Log>,
    artifacts: Vec<Artifact>,
    context: SessionContext,
}
```

### 4. Protocol Bridge

```rust
struct ProtocolBridge {
    state_rx: Receiver<StateChange>,
    event_tx: Sender<Event>,
}

impl ProtocolBridge {
    fn handle_protocol_message(&self, msg: protocol::Message) -> Option<Event> {
        // Convert protocol messages to events
    }
    
    fn handle_state_change(&self, change: StateChange) -> Vec<protocol::Message> {
        // Convert state changes to protocol messages
    }
}
```

## Port Interfaces

### Router Port

```rust
#[async_trait]
trait Router {
    async fn route(&self, input: String, context: Context) -> RouteDecision;
}

struct RouteDecision {
    action: RouteAction,
    reasoning: String,
}

enum RouteAction {
    StartExecution(ExecutorType, String),
    QueryStatus,
    PassThrough(String),
    Respond(String),
}
```

### Executor Port

```rust
#[async_trait]
trait Executor {
    async fn start(&mut self, request: ExecutorRequest) -> Result<SessionId>;
    async fn send(&mut self, message: String) -> Result<()>;
    async fn poll(&mut self) -> Vec<ExecutorOutput>;
    async fn stop(&mut self) -> Result<Summary>;
}
```

### STT Port

```rust
#[async_trait]
trait SpeechToText {
    async fn transcribe(&self, audio: AudioData) -> Result<String>;
}
```

## Application Flow

### Execution Mode Flow

```
1. UserInput → Router
2. Router → RequestExecution event
3. State: Idle → RequestingConfirmation
4. Effect: SendConfirmationRequest
5. User confirms → ConfirmationReceived event
6. State: RequestingConfirmation → Starting
7. Effect: StartExecutor
8. Executor starts → ExecutorStarted event
9. State: Starting → Running
10. Executor outputs → ExecutorOutput events
11. Effects: SaveLogs, SendStatus
12. Executor completes → ExecutorCompleted event
13. State: Running → Completing
14. Effects: SaveSession, SendStatus
15. State: Completing → Idle
```

## Key Improvements Over Current Architecture

### 1. Explicit State Machine
- No implicit states via flags
- All transitions are explicit
- State determines available actions

### 2. Effect System
- Side effects separate from state logic
- Testable state transitions
- Async effects don't block state machine

### 3. Clean Ports
- No protocol knowledge in core
- Swappable implementations
- Easy to test with mocks

### 4. Event-Driven
- No polling loops in core
- React to events, emit effects
- Clean async boundaries

### 5. Session-Centric
- Sessions are first-class entities
- Phases within sessions
- Rich context throughout

## Implementation Strategy

### Phase 1: Core State Machine
1. Implement state types and transitions
2. Build effect system
3. Create event loop
4. Add tests for all transitions

### Phase 2: Protocol Bridge
1. Map protocol messages to events
2. Map state changes to protocol
3. Maintain backward compatibility
4. Test with frozen mobile interface

### Phase 3: Adapters
1. Implement Router adapter
2. Implement Claude executor adapter
3. Implement STT adapter
4. Add mock adapters for testing

### Phase 4: Minimal TUI
1. Simple display of state
2. Input handling
3. No business logic
4. Just a thin view

### Phase 5: Migration
1. Run new and old in parallel
2. Verify mobile compatibility
3. Migrate session history
4. Deprecate old system

## Testing Strategy

### Unit Tests
- State transitions
- Effect generation
- Event handling
- Protocol mapping

### Integration Tests
- Full execution flow
- Session lifecycle
- Error scenarios
- Recovery paths

### Contract Tests
- Mobile interface compatibility
- Protocol message shapes
- Relay protocol compliance

### End-to-End Tests
- Voice command → execution
- Text command → execution
- Status queries
- Confirmation flows

## Future Extensions

### Speccing Mode
- Configuration tree builder
- Phase planner
- Socratic agent

### Inspection Mode
- Demo driver
- Speech-to-action
- Verification flows

### Multi-Executor
- Parallel sessions
- Executor coordination
- Resource management

### Collaboration
- Multi-user sessions
- Shared context
- Conflict resolution

## Success Criteria

1. **Clean Code** - Each component has single responsibility
2. **Testable** - >90% test coverage on core logic
3. **Maintainable** - Easy to understand and modify
4. **Extensible** - New features don't require core changes
5. **Performant** - No blocking operations in hot paths
6. **Compatible** - Mobile app works unchanged