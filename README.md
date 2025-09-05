# CodeWalk

The overarching goal of this project is to allow knowledge workers to spend as much productive time outside of their house by interfacing with their machine at home via voice. With the rise of agents (and computer using agents (CUAs)), voice interfaces are becoming increasingly viable. What is missing right now is the proper stack and interfaces built by people that actually use them. 

Just start this app on your computer, install the app for your phone, link them up via a QR code scan, and you will be having access to your work station while out and about. The end goal is to be able to have a conversation with an orchestrator agent that will help you spec things out, and give you real time narration of the progress of different agents. 

Over time, we will add means of inspectability: 
- Showing recordings of the app you're building
- Selective inspection, like showing code snippets
- Verifier agents and heavy QA testing pipelines

Manual Test (multiple terminals)

1) Prepare `.env` at repo root with `RELAY_WS_URL`, `RELAY_SESSION_ID`, `RELAY_TOKEN` and your groq api key.

2) Terminal A — Relay server

```
   cd relay/server
   cargo run --release --bin relay-server
```

3) Terminal B — Workstation (TUI)

```
   cargo run -p orchestrator --bin codewalk
```

4) Terminal C — App

```
   cd apps/VoiceRelaySwiftUI
   ./run-sim.sh
```

5) Send a message from the app

   Type text and press Send. The app shows “Ack: received”. The TUI prints a `RELAY> user_text: ...` line.

Architecture Overview

- crates/orchestrator-core: Headless business logic. Routes protocol messages, manages confirmation flow, tracks active session context. No UI or I/O.
- crates/orchestrator-adapters: Integrations for router/LLM, relay, and the core bridge. Provides thin adapters that implement orchestrator-core ports.
- crates/control_center: Executor orchestration and log monitoring (Claude Code, etc.). Emits structured logs and abstracts session lifecycles.
- crates/orchestrator: Thin binary and coordination glue. Starts core, wiring adapters and relay. Maintains artifacts and session summaries.
- crates/orchestrator-tui: Terminal UI state and rendering (feature-gated while extraction stabilizes). No business logic.
- crates/router, crates/llm, crates/stt, crates/protocol: Supporting libraries for routing, LLM access, speech-to-text, and message schema.

Logs and Artifacts

- All orchestrator logs now write to `artifacts/orchestrator_*.log`.
- Executor logs default under `artifacts/executor_logs/` and per-run artifacts under `artifacts/`.
- Tail current orchestrator logs with `tail -f artifacts/orchestrator_*.log`.

Testing Notes

- Unit and integration tests target fast completion; individual async waits are capped to <=10s.
- Long-running benches are reduced (iterations=200) to keep CI <10s per test target.

Inter‑Crate Communication

- Messages: All user/system events are represented as `protocol::Message`.
- Channels: The app sets up Tokio mpsc channels.
  - App → Core: `Message::UserText`, `Message::ConfirmResponse`.
  - Core → App/UI: `Message::PromptConfirmation`, `Message::Status`, etc.
- Ports (traits in `orchestrator-core`):
  - `RouterPort::route(text, context) -> RouteResponse` — implemented in adapters using `router` + `llm`.
  - `ExecutorPort::launch/query_status` — implemented against `control_center`.
  - `OutboundPort::send(Message)` — typically a channel sender to UI/relay.

Runtime Shapes
- Headless: Core + adapters run without UI, emitting statuses and summaries.
- TUI: UI crate renders panes and only emits protocol messages; it holds no business logic.
