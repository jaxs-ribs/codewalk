# CodeWalk

CodeWalk connects a phone and a workstation through a relay. The phone sends text (or speech→text); the workstation routes it and can start a coding session. This repo contains all pieces and a one‑command end‑to‑end test.

Get Started

1) Create `.env` at the repo root:

   RELAY_WS_URL=ws://127.0.0.1:3001/ws
   RELAY_SESSION_ID=devsession0001
   RELAY_TOKEN=devtoken0001x

2) Run the end‑to‑end check (starts server + workstation + headless phone):

   cargo run -p xtask -- e2e quick --text 'build a small cli tool please'

You’ll see colored steps, then “E2E(quick) PASS”. For a slightly longer run that also kills the session, use `full` instead of `quick`.

Next

- Workstation UI: `cargo run -p orchestrator --bin codewalk`
- Relay docs: `relay/server/README.md`
- Headless phone: `relay/client-mobile/README.md`

Manual Test (multiple terminals)

1) Prepare `.env` at repo root with `RELAY_WS_URL`, `RELAY_SESSION_ID`, `RELAY_TOKEN`.

2) Terminal A — Relay server

   cd relay/server
   cargo run --release --bin relay-server

3) Terminal B — Workstation (TUI)

   cargo run -p orchestrator --bin codewalk

4) Terminal C — Metro (React Native)

   cd apps/VoiceRelay
   nvm use 22 && npm install && npm start

5) Terminal D — Simulator

   iOS: cd apps/VoiceRelay && npm run ios -- --simulator="iPhone 16 Pro"
   Android: cd apps/VoiceRelay && npm run android

6) Send a message from the app

   Type text and press Send. The app shows “Ack: received”. The TUI prints a `RELAY> user_text: ...` line.

Optional: HTTP ingest from a fifth terminal

   curl -s -X POST http://localhost:3001/api/transcripts \
     -H 'Content-Type: application/json' \
     -d '{"sid":"RELAY_SESSION_ID","tok":"RELAY_TOKEN","text":"build a small cli tool please","final":true,"source":"api"}'
