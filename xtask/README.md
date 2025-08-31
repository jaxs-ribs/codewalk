xtask: Workspace Tasks and E2E Runner

This crate provides project automation. The `e2e` task launches a full, headless pipeline: relay server, headless orchestrator, and a "phone" client that connects to the relay and sends a `user_text` message. It waits for an `ack` from the workstation and fails fast if something is misconfigured.

Usage

1) Ensure `./.env` contains:
   - `RELAY_WS_URL` (e.g., `ws://127.0.0.1:3001/ws`)
   - `RELAY_SESSION_ID`
   - `RELAY_TOKEN`

2) Quick run:
   cargo run -p xtask -- e2e quick --text 'build a small cli tool please'

3) Full run (also kills the session at the end):
   cargo run -p xtask -- e2e full --text 'build a small cli tool please'

What it does
- Builds the workspace with warnings treated as errors.
- Starts the relay server and polls `/health` until ready.
- Starts the orchestrator headless (no TUI) connected to the relay.
- Runs the phone-bot client which sends a `user_text` and waits for an `ack`.
- In `full` mode, sends `DELETE /api/session/:sid`.

On failure, processes are terminated and a non-zero exit status is returned with a concise error. On success you’ll see `E2E(<mode>) PASS`.

