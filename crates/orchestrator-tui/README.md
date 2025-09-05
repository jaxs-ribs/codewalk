Orchestrator TUI

Role
- Terminal UI components and UI-only state. Pure presentation, no business logic.

Responsibilities
- Render output/log panes and dialogs.
- Manage scroll, input buffer, and transient UI state.

Interfaces
- Emits and consumes `protocol::Message` through channels provided by the app layer.
- Depends on: `protocol`, optional TUI crates.

Notes
- The UI modules are feature-gated while extraction stabilizes. Keep this crate free of routing or executor logic.

