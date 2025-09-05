# CodeWalk Rust Workspace — Crates Overview

This document orients you within the `crates/` workspace: what each crate does, how they communicate, and where to look when adding features or debugging.

## What Lives Here

- orchestrator: Thin startup binary. Wires the core, adapters, relay, and optional TUI; owns local artifacts.
- orchestrator-core: Business brain. Pure logic plus small session context; routes messages and manages confirmation.
- orchestrator-adapters: Real-world integrations. Implements core ports (router/llm, outbound/relay, bridge) with side effects.
- control_center: Executor management and log monitoring. Spawns the code executor (Claude Code) and normalizes logs.
- orchestrator-tui: Terminal UI crate. Pure presentation (draw, input, scroll); no business logic.
- router: LLM-assisted text routing utilities used by adapters.
- llm: Thin client to LLM providers (e.g., Groq) consumed by the router/adapters.
- protocol: Shared message schema (`protocol::Message` and payloads) across the system.
- stt: Optional local audio recorder + speech-to-text helpers for TUI mic flows.

## How Things Talk (Message Flow)

- User input enters via TUI or Relay as `protocol::Message::UserText`.
- orchestrator forwards inbound messages to orchestrator-core.
- orchestrator-core:
  - calls `RouterPort::route(text, context)` (implemented in adapters using `router` + `llm`)
  - emits `PromptConfirmation` when an executor launch is recommended
  - consumes `ConfirmResponse` and calls `ExecutorPort::launch(prompt)`
  - answers status queries via `ExecutorPort::query_status()` → `Status`
- control_center launches the executor (Claude Code), manages its lifecycle, and streams logs.
- orchestrator consumes core outbounds and updates UI/relay.

## The Ports (Core Boundaries)

- RouterPort: `route(text, context) -> RouteResponse`
  - Decides: `LaunchClaude`, `QueryExecutor`, or `CannotParse`.
- ExecutorPort: `launch(prompt)`, `query_status()`
  - Bridges to control_center (spawn process, monitor status).
- OutboundPort: `send(protocol::Message)`
  - Emits core results to UI or relay via channels.

## Run Modes

- Headless: No UI. Core emits `Status` and summaries; good for automation or relay-only.
- TUI: Uses `orchestrator-tui` for a terminal interface. UI emits/consumes only `protocol::Message`.
- Feature flags:
  - `tui`, `tui-stt`, `tui-input` (UI/mic/input features)
  - Adapters declare `tui`/`tui-stt` flags to silence cfg warnings where relevant

## Artifacts & Logs

- Orchestrator logs: `artifacts/orchestrator_*.log`
- Executor logs (default, workspace-local): `artifacts/executor_logs/`
  - Interactive Claude may also write under the user’s Claude projects dir; the log monitor handles both.
- Session artifacts (summaries, metadata): under `artifacts/`

## Add a New Integration

1) Implement a core port:
   - Router: create a type implementing `RouterPort` (call out to your router/llm).
   - Executor: implement `ExecutorPort` or extend `control_center` with a new `ExecutorType` + factory hook.
   - Outbound: adapt to your transport (e.g., relay) by implementing `OutboundPort` and passing a channel sender.
2) Wire it in orchestrator (binary) where channels and adapters are created.
3) Add concise tests in the relevant crate; keep per-test runtime < ~10s.

## Source Pointers (Jump-in Spots)

- Core routing/confirm logic: `orchestrator-core/src/lib.rs`
- Executor handling + logs: `control_center/src/executor/*`, `control_center/src/logs.rs`
- Adapter bridge/router: `orchestrator-adapters/src/bridge/`, `orchestrator-adapters/src/groq/`
- Binary glue: `orchestrator/src/app.rs`, `orchestrator/src/core_bridge.rs`, `orchestrator/src/logger.rs`
- UI: `orchestrator-tui/src/` (feature-gated modules)
- Protocol schema: `protocol/src/`

## Conventions

- No business logic in TUI. Only presentation and input handling.
- No network/process side effects in core. Use adapters to isolate I/O.
- Keep logs and artifacts under `artifacts/` for easy discovery and CI hygiene.
- Prefer protocol messages and channels for cross-crate communication.

## Quick Troubleshooting

- Confirmation loop or missing launches:
  - Check latest orchestrator log under `artifacts/`; verify `PromptConfirmation` → `ConfirmResponse` → `Status` messages are present.
  - Ensure the `claude` CLI is installed and on `$PATH` for interactive mode.
- Status queries feel “stuck”:
  - Confirm active session context in core and that `QueryExecutor` maps to `query_status()`.
- Logs not appearing:
  - For headless runs, stdout is parsed; for interactive sessions, ensure the log monitor points at the correct directory.

## Terminology

- Session: A single executor run (interactive or headless), optionally resumable.
- Context: Lightweight info used by the router (e.g., has active session?).
- Artifacts: On-disk outputs (summaries, history), separate from transient logs.

Happy hacking. Keep modules small, boundaries clean, and messages explicit.

## Architecture Diagram (Mermaid)

```mermaid
flowchart LR
  %% Groups
  subgraph UI
    TUI[TUI]:::ui
    Relay[Relay Client]:::ui
  end
  subgraph Orchestrator
    App[orchestrator (binary glue)]:::app
    Core[orchestrator-core]:::core
  end
  subgraph Adapters
    Bridge[orchestrator-adapters\n(Ports impl)]:::adp
    RouterCrate[router]:::lib
    LLM[llm]:::lib
  end
  subgraph Exec
    Ctr[control_center]:::exec
    Claude[Claude Code CLI]:::exec
  end
  Prot[protocol]:::lib

  %% Message flow
  TUI -- UserText --> App
  Relay -- UserText --> App
  App -- Message --> Core

  Core -- RouterPort::route --> Bridge
  Bridge -- uses --> RouterCrate
  RouterCrate -- uses --> LLM
  Bridge -- RouteResponse --> Core

  Core -- PromptConfirmation/Status --> App
  App -- UI updates --> TUI
  App -- Relay frames --> Relay

  Core -- ExecutorPort::launch/query_status --> Ctr
  Ctr -- spawn --> Claude
  Claude -- stdout/stream-json --> Ctr
  Ctr -- ParsedLogLine --> App

  %% Shared schema relation (dotted)
  Prot -. shared .- Core
  Prot -. shared .- App
  Prot -. shared .- Bridge
  Prot -. shared .- TUI
  Prot -. shared .- Relay

  %% Styles
  classDef app fill:#eef,stroke:#88a,stroke-width:1px;
  classDef core fill:#efe,stroke:#8a8,stroke-width:1px;
  classDef adp fill:#fee,stroke:#a88,stroke-width:1px;
  classDef exec fill:#fef,stroke:#a8a,stroke-width:1px;
  classDef ui  fill:#eef9ff,stroke:#66a,stroke-width:1px;
  classDef lib fill:#f9f9f9,stroke:#aaa,stroke-width:1px;
```
