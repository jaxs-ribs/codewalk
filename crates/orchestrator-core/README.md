Orchestrator Core

Role
- Headless business logic for CodeWalk. Receives protocol messages, makes routing decisions, manages confirmation flow, and tracks active session context.

Key Concepts
- RouterPort: trait for routing user text into actions (e.g., LaunchClaude, QueryExecutor, CannotParse).
- ExecutorPort: trait to launch/query the active code executor (Claude Code, etc.).
- OutboundPort: trait to emit `protocol::Message` back to the UI/relay.
- Session state: lightweight context of whether an executor is active (used to avoid status loops).

Message Flow
- Inbound: `protocol::Message::UserText` and `ConfirmResponse`.
- Outbound: `PromptConfirmation`, `Status`, and others as needed.

Used By
- `orchestrator` (binary) to coordinate runtime.
- `orchestrator-adapters` to bind real router/llm and relay clients.

Does Not
- Render UI.
- Perform network I/O directly.

