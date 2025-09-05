Router

Role
- LLM-assisted router utilities to interpret user text and recommend actions.

Responsibilities
- Provide an API to transform text into a structured router response (e.g., LaunchClaude, CannotParse) used by a RouterPort adapter.

Interfaces
- Used by: `orchestrator-adapters` to implement `RouterPort` against the core.
- Depends on: `llm` for model calls (when applicable).

