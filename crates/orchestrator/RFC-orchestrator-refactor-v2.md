# RFC: Orchestrator Refactor v2 — Consolidate, Don’t Multiply

Date: September 2025
Author: Architecture Team
Status: Draft

## Executive Summary

Keep the hexagonal intent, but avoid introducing redundant crates. Expand `orchestrator-core` as the domain brain, reuse existing crates (`router`, `control_center`, `llm`, `stt`), and move adapters into a small `adapters/` module inside `orchestrator` (or split later if/when they grow). Unify routing and confirmation through the core to eliminate duplicated logic and the “Query Status” loop. Optionally extract the TUI into its own crate once the orchestration surface is thin.

Key principles:
- One brain (`orchestrator-core`) owns routing/confirmation/session context state machines.
- Zero LLM/STT calls from UI or relay paths; UI only emits/consumes `protocol::Message`.
- Reuse `control_center` for executor runtime + logs instead of creating a new crate.
- Introduce small, explicit adapters to bridge ports to existing crates.
- Keep changes incremental: fix correctness first, modularize next, extract crates last.

## What’s Broken Today (validated in code)

- Monolithic `App` mixes UI, orchestration, storage, and integrations (`crates/orchestrator/src/app.rs`).
- Two confirmation paths exist: local analyzer in `confirmation_handler.rs` vs core-driven `ConfirmResponse` in `handlers.rs` → creates drift and LLM misroutes.
- UI calls LLM routing directly (`backend::text_to_llm_cmd`) instead of going through the core.
- Session history and artifact writes live in the TUI app and bleed into orchestration logic.

## Goals (unchanged intent, pragmatic scope)

- Make business flows testable without TUI, relay, or network.
- Fix confirmation flow: all confirmation decisions go through the core; UI only displays and forwards.
- Keep crate count stable by reusing `router`, `control_center`, `llm`, `stt`.
- Shrink the `App` to UI state and thin coordination.

## Proposed Architecture

### Crates to keep (no new crates now)

- `orchestrator-core`: domain core (expand here)
- `control_center`: executor runtime + logs (reuse as-is; optional rename later)
- `router`: routing via LLM providers (Groq already exists)
- `llm`, `stt`, `protocol`: reuse as-is
- `orchestrator`: thin binary + adapters + TUI (TUI remains behind feature flags; optional extraction later)

### Domain core (expand, but keep pure)

`orchestrator-core` owns:
- Routing decision flow (LaunchClaude, CannotParse, QueryExecutor)
- Confirmation gate (PromptConfirmation → ConfirmResponse → launch)
- Minimal session context (active/not active, session type)

Avoid putting storage/LLM/STT into the core. If/when session persistence is needed, add a minimal `SessionStore` port, but keep implementations out of the core.

Ports (current + optional):
- `RouterPort` (exists): route(text, context) → decision
- `ExecutorPort` (exists): launch(prompt), query_status() → String
- `OutboundPort` (exists): emit `protocol::Message`
- Optional later: `SessionStore` (load/save session summaries/ids) — only when resume pathways need core involvement

### Adapters (module, not a crate)

Add `orchestrator/src/adapters/` to bridge ports to existing crates:
- `router.rs`: wraps `router::{GroqProvider,...}` into `RouterPort`
- `executor.rs`: wraps `control_center` into `ExecutorPort` using the existing `AppCommand` channel
- `outbound.rs`: channel-based `OutboundPort` (already in `core_bridge.rs` → move here)
- `session_store.rs` (later): file-backed summary/metadata using current `artifacts/` layout
- `summarizer.rs` (stay in orchestrator): uses `llm` for summaries; remains outside the core; consumed by `ExecutorPort::query_status()` handler

This keeps external deps out of the core, avoids a new `orchestrator-adapters` crate, and leverages current code.

### TUI boundary

- Keep TUI behind `tui`, `tui-stt`, `tui-input` features (already exists).
- Shrink `App` into `TuiState` (pure UI state: buffers, scroll, selected tab). Move orchestration into adapters/core.
- UI events only translate to `protocol::Message` to the core or to internal UI state changes. No direct calls to LLM/STT except audio capture, which becomes input → text → Message.

### Message flow (single source of truth)

1. UI/Relay emits `protocol::Message::UserText` to the core.
2. Core routes via `RouterPort`.
3. If LaunchClaude and confirmation required → core emits `PromptConfirmation`.
4. UI displays confirmation and returns `ConfirmResponse` to the core.
5. Core calls `ExecutorPort.launch()` and updates outbound status.
6. For status queries, core calls `ExecutorPort.query_status()`; the adapter returns a string summary (leveraging existing summarizer + logs in orchestrator).

Special case — voice confirmation:
- When mode is ConfirmingExecutor and input is a short voice response, the UI should intercept text and convert it to `ConfirmResponse` using `router::confirmation` locally, then send to the core. Do not send voice confirmation through LLM routing.

## What We’re Not Doing (yet)

- Creating `executor-toolkit` (we already have `control_center` with runtime + logs).
- Creating `orchestrator-adapters` (adapters live as modules until they justify their own crate).
- Moving summarization into the core (keeps core pure and tests fast).
- Renaming crates or changing public APIs across the workspace.

## Incremental Migration Plan

Phase 0: Instrument and freeze interfaces (1–2 days)
- Add structured logs around routing and confirmation paths to confirm the “Query Status” loop is eliminated.
- Decide default: `require_confirmation = true` in core (already the case).

Phase 1: Unify routing through core (2–3 days)
- Replace `App::route_command`’s direct calls to `backend::text_to_llm_cmd` with `core_in_tx.send(protocol::Message::UserText(...))`.
- In `confirmation_handler.rs`, stop launching directly. Always send `ConfirmResponse` to the core. Keep local analyzer only to turn free-form voice answers into concrete confirmation actions.
- Ensure `handlers.rs` Enter/Esc paths already issue `ConfirmResponse` (they do).

Phase 2: Isolate adapters (2–4 days)
- Move `core_bridge.rs` contents into `orchestrator/src/adapters/{router.rs,executor.rs,outbound.rs}`.
- Keep `ExecutorAdapter` using the current `AppCommand` channel to reach `ControlCenter` and summarizer logic.
- Remove LLM/stt usage from anywhere but adapters and TUI audio input.

Phase 3: Session persistence port (optional, 2–3 days)
- Introduce a `SessionStore` port in the core only if resume logic must be driven by core.
- Implement a file-based adapter that wraps the current `artifacts/` JSON read/write.
- Wire `--resume <session_id>` handling at the binary layer and publish a `set_active_session` into the core context.

Phase 4: Optional TUI extraction (3–5 days)
- Once orchestration is thin: move `ui/` and input handlers into `orchestrator-tui` (new crate) gated by features.
- Keep `orchestrator` as thin binary wiring + adapters.

## Minimal Code Changes (first pass)

- In `crates/orchestrator/src/app.rs`, change `route_command` to send to core:
  - Before: calls `backend::text_to_llm_cmd` and parses `RouterResponse` locally.
  - After: `tx.send(protocol::Message::UserText({...}))` and let core emit `PromptConfirmation` or `Status`.
- In `crates/orchestrator/src/confirmation_handler.rs`, remove local launching; on “continue/new/no”, send `ConfirmResponse` only.
- In `crates/orchestrator/src/core_bridge.rs`, move adapters into `orchestrator/src/adapters/` with unchanged signatures.
- Keep `crates/control_center` untouched; maintain log monitor and executor sessions.

This preserves behavior, removes duplication, and makes routing/confirmation testable via core examples.

## Testing Strategy

Unit (core):
- Route text with and without active session context.
- Emit `PromptConfirmation` and handle `ConfirmResponse`.
- Verify `QueryExecutor` returns a status string and never launches.

Integration (orchestrator):
- Voice confirmation: “yes/new/no” during ConfirmingExecutor causes a single `ConfirmResponse` and no LLM calls.
- Status queries while executor is running produce summaries via `ExecutorPort.query_status()`.
- Resume flows keep logs and session ids consistent in `artifacts/`.

Smoke (E2E):
- “help me with a coding task” → `PromptConfirmation` → Enter → executor starts → status query returns friendly summary.

## Success Metrics

- No LLM calls from the UI path (verified via logs and code search).
- Confirmation has a single source of truth in `orchestrator-core`.
- `App` shrinks by ≥25% (UI-only fields; orchestration removed).
- New and existing tests pass without TUI/relay.

## Risks and Mitigations

- Risk: Over-splitting into many crates. Mitigation: keep adapters as modules; only extract later if size/ownership warrants.
- Risk: Behavior drift while removing UI-based routing. Mitigation: Phase 0 logging + side-by-side validation of core vs current behavior.
- Risk: Summarizer differences. Mitigation: keep summarizer out of core; treat summaries as UI-presentational, not domain-critical.

## Conclusion

We keep the spirit of the original RFC—clean boundaries and a domain core—while avoiding new crates that duplicate existing ones. By unifying routing/confirmation in the core, moving integrations behind small adapters, and keeping summarization out of the core, we reduce complexity now and keep the door open for a later, clean TUI extraction.

