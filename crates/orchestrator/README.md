Orchestrator (Binary)

Role
- Thin startup binary and coordination layer. Wires the core, adapters, UI (optional), and relay.

Responsibilities
- Initialize channels and spawn tasks.
- Maintain session summaries/artifacts and route messages to/from the core and relay.

Interfaces
- Depends on: `orchestrator-core`, `control_center`, `orchestrator-adapters`, `protocol`.
- Optional: `orchestrator-tui` for terminal UI.

Artifacts & Logs
- Orchestrator logs: `artifacts/orchestrator_*.log`.
- Session summaries and metadata saved under `artifacts/`.

