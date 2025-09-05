Control Center

Role
- Executor orchestration and log monitoring. Launches/terminates code executor sessions (e.g., Claude Code) and streams structured logs.

Responsibilities
- Provide `ExecutorType` factory and `ExecutorSession` impls.
- Tail executor logs and normalize into `ParsedLogLine` entries.

Interfaces
- Depends on OS process spawning and filesystem.
- Used by: `orchestrator` for session lifecycle; `orchestrator-core` indirectly via an `ExecutorPort` adapter.

Notes
- Defaults point logs under `artifacts/`. Interactive Claude runs write under the user's Claude projects dir; headless runs stream JSON to stdout.

