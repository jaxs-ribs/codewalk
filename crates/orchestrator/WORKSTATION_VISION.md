# Workstation Vision: Walking-Coding Lifecycle

## Overview

The workstation orchestrator manages a complete work lifecycle for coding while walking. Users control everything via a mobile app through a voice agent, with the orchestrator running on a home workstation connected via relay server.

## Core Concept: Work Lifecycle Management

The orchestrator is not just a message router - it's a **work session manager** that guides users through defining, executing, and verifying phased work.

## The Three Primary Modes

### 1. Speccing Mode
Building the work definition through two spaces:

**Configuration Space**
- Build a hierarchical constraint tree
- Define requirements and deliverables
- Agent provides Socratic questioning
- Output: Complete specification of what to build

**Phase Space**
- Break configuration into bite-sized executable chunks
- Each phase has explicit observables and deliverables
- Define both automated and human verification criteria
- Output: Sequenced phases ready for execution

### 2. Execution Mode
Running phase-based work with the following sub-states:

**Running**
- Executor works on current phase
- Can query status at any time
- Progress toward defined deliverables

**Interrupted**
- Accept follow-up instructions
- Modify approach mid-phase
- Resume execution with new context

**Phase Complete**
- Deliverables achieved
- Ready to verify or continue
- Can review what was done

### 3. Inspection Mode
Verification and demonstration of completed work:

**Review**
- Show what was implemented
- Explain architectural decisions
- Display test results

**Verification**
- Live demonstration of functionality
- For web apps: Playwright-driven testing
- Speech-to-action translation for steering demos

**Screen Sharing**
- Live stream of agent actions
- Visual confirmation of behavior
- Interactive testing with user

## State Machine Architecture

This is a **hierarchical state machine** where:
- Top-level states represent major modes
- Each mode has sub-states for specific activities
- Transitions between any states are allowed
- Context accumulates through the session

```
Workstation
├── Speccing
│   ├── Configuration Building
│   └── Phase Planning
├── Executing
│   ├── Running
│   ├── Interrupted
│   └── Phase Complete
└── Inspecting
    ├── Review
    ├── Verification
    └── Screen Sharing
```

## Key Architectural Principles

### 1. Clean Separation of Concerns
- **Orchestrator Core**: Manages work lifecycle and state machine
- **Frontends (TUI/Mobile)**: Pure presentation, no business logic
- **Router**: Context-aware message routing based on current state
- **Executors**: Phase runners (Claude, Devin, etc.)

### 2. Rich Context Management
The orchestrator maintains:
- **Spec Context**: Configuration tree and phase plan
- **Execution Context**: Current phase, completed phases, accumulated knowledge
- **Session Context**: Full history enabling resume/interrupt/continue

### 3. Phase-Based Sessions
- Sessions span multiple phases
- Each phase has success criteria
- Phases build on each other
- Can pause between phases

### 4. Event-Driven Architecture
- Phase transitions trigger events
- State changes are reactive, not polled
- Clear separation between states and transitions

## Future Extensions

### Near Term
- Multiple executor support
- Richer phase dependencies
- Automated verification frameworks

### Long Term
- Computer-using agents for full automation
- Multi-modal verification (vision, code analysis)
- Collaborative sessions with multiple users
- Learning from completed sessions

## Implementation Philosophy

1. **Start simple, maintain flexibility**: Begin with execution mode, but architect for full lifecycle
2. **Frontends are thin**: All logic in orchestrator core
3. **State machine first**: Well-defined states and transitions before features
4. **Context is king**: Router and executors need full context to make good decisions
5. **Phases over prompts**: Think in deliverables, not individual commands

## Success Criteria

The architecture succeeds when:
- Adding new frontends requires no core changes
- New modes can be added without breaking existing ones
- State transitions are explicit and recoverable
- Sessions can be paused, resumed, and shared
- The system guides users through complex work naturally