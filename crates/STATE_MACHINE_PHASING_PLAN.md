# State Machine Implementation Phasing Plan

## Core Insight

The hierarchical state machine IS the system. Everything else (UI, protocols, executors) are just I/O adapters. If we get the state machine right, with all states and transitions properly defined, the rest of the implementation becomes straightforward.

## Phase 1: Complete State Machine Specification
**Goal**: Define EVERY state, substate, transition, and guard condition

### 1.1 State Hierarchy Definition
```rust
enum WorkstationState {
    Idle,
    Speccing(SpecState),
    Executing(ExecutionState),  
    Inspecting(InspectionState),
    Error(ErrorState),
}

enum SpecState {
    GatheringContext,           // Initial understanding of user's goal
    BuildingConfiguration {     // Creating constraint tree
        tree: ConfigTree,
        depth: usize,
    },
    ValidatingConfiguration {   // Checking completeness
        tree: ConfigTree,
        issues: Vec<ValidationIssue>,
    },
    PlanningPhases {           // Breaking into executable phases
        config: ConfigTree,
        phases: Vec<Phase>,
    },
    ReviewingPlan {            // User reviews before execution
        plan: ExecutionPlan,
    },
}

enum ExecutionState {
    RequestingConfirmation {
        request: ExecutionRequest,
        confirmation_id: String,
    },
    Launching {
        request: ExecutionRequest,
    },
    Running {
        session: Session,
        phase: Phase,
        logs: Vec<LogEntry>,
    },
    Paused {                  // User interrupted
        session: Session,
        reason: String,
        can_resume: bool,
    },
    WaitingForInput {         // Executor needs user input
        session: Session,
        prompt: String,
    },
    Completing {
        session: Session,
        results: PhaseResults,
    },
}

enum InspectionState {
    SelectingMode {
        session: Session,
        available_modes: Vec<InspectionMode>,
    },
    ReviewingArtifacts {
        session: Session,
        artifacts: Vec<Artifact>,
        current_index: usize,
    },
    RunningDemo {
        session: Session,
        demo_script: DemoScript,
        current_step: usize,
    },
    VerifyingBehavior {
        session: Session,
        test_suite: TestSuite,
        results: Vec<TestResult>,
    },
    GeneratingReport {
        session: Session,
        report_type: ReportType,
    },
}

enum ErrorState {
    Recoverable {
        from_state: Box<WorkstationState>,
        error: Error,
        recovery_options: Vec<RecoveryOption>,
    },
    Fatal {
        error: Error,
        cleanup_needed: bool,
    },
}
```

### 1.2 Event Definitions
```rust
enum Event {
    // User inputs
    UserMessage(String),
    UserConfirmation { id: String, accepted: bool },
    UserCancellation,
    
    // Spec events
    SpecRequested { goal: String },
    ConfigNodeAdded { node: ConfigNode },
    ConfigValidated { valid: bool },
    PhaseGenerated { phase: Phase },
    PlanApproved,
    
    // Execution events  
    ExecutionRequested { prompt: String },
    ExecutorLaunched { session_id: String },
    ExecutorOutput { content: String, output_type: OutputType },
    ExecutorCompleted { summary: String },
    ExecutorFailed { error: String },
    ExecutorNeedsInput { prompt: String },
    
    // Inspection events
    InspectionRequested { session_id: String },
    DemoStepCompleted { step_id: String },
    VerificationPassed { test_id: String },
    ArtifactSelected { artifact_id: String },
    
    // System events
    Timeout { context: String },
    ResourcesLow { resource: ResourceType },
}
```

### 1.3 Transition Rules Matrix

| From State | Event | Guard Condition | To State | Effects |
|------------|-------|----------------|----------|---------|
| Idle | SpecRequested | has_goal | Speccing::GatheringContext | InitializeSpecSession |
| Idle | ExecutionRequested | has_prompt | Executing::RequestingConfirmation | GenerateConfirmationId |
| Idle | InspectionRequested | has_valid_session | Inspecting::SelectingMode | LoadSession |
| Speccing::GatheringContext | UserMessage | is_clarification | Speccing::BuildingConfiguration | StartConfigTree |
| Speccing::BuildingConfiguration | ConfigNodeAdded | tree_incomplete | Speccing::BuildingConfiguration | UpdateTree |
| Speccing::BuildingConfiguration | ConfigNodeAdded | tree_complete | Speccing::ValidatingConfiguration | ValidateTree |
| Speccing::ValidatingConfiguration | ConfigValidated | is_valid | Speccing::PlanningPhases | GeneratePhases |
| Speccing::PlanningPhases | PhaseGenerated | more_phases_needed | Speccing::PlanningPhases | AddPhase |
| Speccing::PlanningPhases | PhaseGenerated | plan_complete | Speccing::ReviewingPlan | PreparePlanSummary |
| Speccing::ReviewingPlan | PlanApproved | - | Executing::RequestingConfirmation | ConvertToExecutionRequest |
| Executing::RequestingConfirmation | UserConfirmation | accepted | Executing::Launching | StartExecutor |
| Executing::Launching | ExecutorLaunched | - | Executing::Running | InitializeSession |
| Executing::Running | ExecutorOutput | is_progress | Executing::Running | LogOutput |
| Executing::Running | ExecutorNeedsInput | - | Executing::WaitingForInput | PauseExecution |
| Executing::WaitingForInput | UserMessage | is_response | Executing::Running | ResumeWithInput |
| Executing::Running | ExecutorCompleted | - | Executing::Completing | GenerateSummary |
| Executing::Completing | UserMessage | wants_inspection | Inspecting::SelectingMode | TransitionToInspection |
| Executing::Completing | UserMessage | wants_next_phase | Executing::RequestingConfirmation | PrepareNextPhase |
| Inspecting::SelectingMode | UserMessage | selected_review | Inspecting::ReviewingArtifacts | LoadArtifacts |
| Inspecting::SelectingMode | UserMessage | selected_demo | Inspecting::RunningDemo | PrepareDemo |
| Inspecting::ReviewingArtifacts | ArtifactSelected | - | Inspecting::ReviewingArtifacts | DisplayArtifact |
| Any | UserCancellation | can_cancel | Previous/Idle | Cleanup |
| Any | Timeout | - | Error::Recoverable | SaveState |

### 1.4 Guard Conditions
```rust
fn has_goal(event: &Event) -> bool
fn has_prompt(event: &Event) -> bool  
fn tree_complete(state: &SpecState) -> bool
fn is_valid(validation: &ValidationResult) -> bool
fn more_phases_needed(state: &SpecState) -> bool
fn can_cancel(state: &WorkstationState) -> bool
fn accepted(confirmation: &UserConfirmation) -> bool
```

### 1.5 Effects (Side Effects)
```rust
enum Effect {
    // Session management
    InitializeSpecSession { goal: String },
    InitializeExecutionSession { request: ExecutionRequest },
    SaveSession { session: Session },
    
    // External calls
    StartExecutor { request: ExecutionRequest },
    StopExecutor { session_id: String },
    SendToRouter { message: String, context: Context },
    
    // User communication  
    RequestConfirmation { id: String, prompt: String },
    SendStatus { message: String },
    ShowError { error: String },
    
    // Internal processing
    GeneratePhases { config: ConfigTree },
    ValidateConfiguration { tree: ConfigTree },
    GenerateSummary { logs: Vec<LogEntry> },
}
```

## Phase 2: Pure State Machine Implementation
**Goal**: Implement the state machine with NO external dependencies

### 2.1 Core State Machine
```rust
// Pure functional core - no async, no I/O
impl StateMachine {
    fn transition(&mut self, event: Event) -> Result<Vec<Effect>, TransitionError> {
        // Match current state + event -> new state + effects
        // This is the ENTIRE business logic
    }
}
```

### 2.2 Comprehensive Tests
- Test EVERY transition in the matrix
- Test guard conditions
- Test invalid transitions
- Test error states
- Property-based testing for state invariants

## Phase 3: Effect Handlers
**Goal**: Implement the bridge between pure state machine and real world

### 3.1 Effect Runtime
```rust
#[async_trait]
trait EffectHandler {
    async fn handle(&self, effect: Effect) -> Result<Vec<Event>>;
}
```

### 3.2 Mock Handlers for Testing
- MockExecutor (returns canned responses)
- MockRouter (returns predetermined routes)
- MockConfirmer (auto-accepts/rejects)

## Phase 4: Real Adapters
**Goal**: Connect to actual external systems

### 4.1 Protocol Adapter
- Maps protocol messages → Events
- Maps Effects → protocol messages
- Maintains backward compatibility

### 4.2 Executor Adapter
- Launches Claude/Devin
- Streams output → Events
- Handles process lifecycle

### 4.3 Router Adapter
- Calls LLM API
- Parses decisions → Events

## Phase 5: Transport Layer
**Goal**: Handle message transport

### 5.1 Relay Client
- WebSocket connection
- Frame wrapping/unwrapping
- Reconnection logic

### 5.2 Event Loop
```rust
async fn run_system(
    state_machine: StateMachine,
    effect_runtime: EffectRuntime,
    event_receiver: Receiver<Event>,
) {
    loop {
        let event = event_receiver.recv().await;
        let effects = state_machine.transition(event)?;
        let new_events = effect_runtime.handle(effects).await?;
        // Feed new events back
    }
}
```

## Phase 6: Web UI
**Goal**: Create web interface (skip TUI entirely)

### 6.1 WebSocket Server
- Expose state changes as events
- Accept commands as events
- Real-time updates

### 6.2 React/Vue Frontend
- Display current state
- Show available actions
- Render session history
- Handle user input

## Validation Checkpoints

### After Phase 1 (State Machine Spec)
- [ ] Every possible user flow is covered
- [ ] All error cases have transitions
- [ ] State machine is deterministic
- [ ] No orphan states
- [ ] Effects cover all side effects

### After Phase 2 (Implementation)
- [ ] 100% test coverage on transitions
- [ ] State machine is pure (no I/O)
- [ ] Transitions are fast (<1ms)
- [ ] State can be serialized/restored

### After Phase 3 (Effect Handlers)
- [ ] Can run entire flows with mocks
- [ ] Effects are idempotent where possible
- [ ] Error handling is comprehensive

### After Phase 4 (Real Adapters)
- [ ] Mobile protocol works unchanged
- [ ] Claude launches successfully
- [ ] Router makes correct decisions

### After Phase 5 (Transport)
- [ ] Mobile app connects and works
- [ ] Messages flow correctly
- [ ] Reconnection works

### After Phase 6 (Web UI)
- [ ] State is accurately displayed
- [ ] All actions are accessible
- [ ] Real-time updates work

## Critical Success Factors

1. **State Machine Completeness**: Every scenario is handled
2. **Pure Functional Core**: State machine has no side effects
3. **Effect Isolation**: All I/O happens through effects
4. **Testability**: Can test all logic without real systems
5. **Clarity**: State machine is self-documenting

## Why This Order?

1. **State machine first** because it IS the system
2. **Pure implementation** ensures correctness
3. **Effects next** to bridge pure logic to real world
4. **Adapters** can be swapped/mocked easily
5. **Transport** is just plumbing
6. **UI last** because it's just a view

The key insight: Once we have a complete, correct state machine, everything else is just connecting it to the outside world. The state machine is the specification, the documentation, and the implementation all in one.

## Next Step

Review the state hierarchy and transition matrix above. Once we agree on these, implementing the pure state machine is straightforward. The hard part is getting the states and transitions right - the code is just a reflection of that design.