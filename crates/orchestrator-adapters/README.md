Orchestrator Adapters

Role
- Concrete integrations that implement orchestrator-core ports:
  - RouterPort via LLM-backed router
  - OutboundPort channel helpers
  - Relay/WebSocket client

Responsibilities
- Initialize providers (LLM, optional STT) and translate between external SDKs and core traits.
- Keep side effects (network, sockets) out of the core.

Interfaces
- Depends on: `orchestrator-core`, `router`, `llm`, `protocol`.
- Provides: implementations of RouterPort/OutboundPort to the app.

Notes
- Feature flags are declared to silence cfg warnings; the UI and STT are optional.

