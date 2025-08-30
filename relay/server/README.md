# Relay Server I/O

 The relay server pairs a workstation with a phone over a short‑lived session so they can exchange app messages without direct connectivity. The workstation calls POST /api/register to mint a session and QR payload. Both peers open a WebSocket to /ws and must first send a hello JSON with sessionId, token, and role (workstation or phone). If valid, the server replies hello-ack, emits peer-joined/peer-left, and relays whatever one side sends (text/binary) to the opposite role as frame events. Sessions expire on idle; clients send hb to refresh TTL; DELETE /api/session/:id kills immediately. Typical flow: desktop shows a QR, mobile scans and connects, and the two exchange plain text or JSON frames while Redis pub/sub routes messages.

## Connection Flow (Exact Order)

- 1) Workstation registers a session:
  - `curl -s -X POST http://localhost:3001/api/register`
  - Save `sessionId` (sid), `token` (tok), and `ws` (WebSocket URL).
- 2) Workstation connects to `ws` and immediately sends hello:
  - `{"type":"hello","s":"<sid>","t":"<tok>","r":"workstation"}`
  - Expect: `{"type":"hello-ack","sessionId":"<sid>"}`
- 3) Phone connects to the same `ws` and sends hello using values from the QR payload:
  - `{"type":"hello","s":"<sid>","t":"<tok>","r":"phone"}`
  - Expect: `{"type":"hello-ack","sessionId":"<sid>"}`
- 4) Both sides receive peer notifications when the other side joins/leaves:
  - Joined: `{"type":"peer-joined","role":"workstation|phone"}`
  - Left: `{"type":"peer-left","role":"workstation|phone"}`
- 5) After both hellos, any plain text frame you send is relayed to the opposite role, delivered as a JSON envelope:
  - Receiver sees: `{"type":"frame","sid":"<sid>","fromRole":"workstation|phone","at":<ts>,"frame":"<your_text>","b64":false}`
- 6) Send heartbeats while idle to keep the session alive:
  - Send: `{"type":"hb"}`; server may reply `{"type":"hb-ack"}` and refresh TTL
- 7) If someone calls `DELETE /api/session/<sid>`, both peers receive `{"type":"session-killed"}` and the socket closes.

Rules
- First message must be `hello` or the server will close.
- Messages only relay to the opposite role (no echo to sender, no same-role fan-out).
- No backfill: frames sent before the opposite role has joined are not delivered later.

## Workstation

- Register session (gets `sessionId`, `token`, `ws`, and QR):
  - Command:
    - `curl -s -X POST http://localhost:3001/api/register`
  - Expected output (example):
    - `{ "sessionId":"2d5a1d6d9b3a4c0b8f92b2bb8c5b1b3f", "token":"6af04d6a5a8e4f2caaeced9b88a8a4b1", "ttl":7200, "ws":"ws://localhost:3001/ws", "qrDataUrl":"data:image/png;base64,iVBORw0...", "qrPayload": { "u":"ws://localhost:3001/ws", "s":"2d5a1d6d9b3a4c0b8f92b2bb8c5b1b3f", "t":"6af04d6a5a8e4f2caaeced9b88a8a4b1" } }`

- Connect to WebSocket and identify:
  - First client message (JSON text frame):
    - `{ "type":"hello", "s":"<sessionId>", "t":"<token>", "r":"workstation" }`
  - Expected server response:
    - `{ "type":"hello-ack", "sessionId":"<sessionId>" }`
  - When the phone joins, you receive:
    - `{ "type":"peer-joined", "role":"phone" }`

- Send text payloads (relayed to the phone):
  - Client sends a plain text frame (e.g., `"hi-from-workstation"`).
  - Phone receives a wrapped relay frame:
    - `{ "type":"frame", "sid":"<sessionId>", "fromRole":"workstation", "at":<unix_ts>, "frame":"hi-from-workstation", "b64":false }`

- Heartbeat (keeps session alive):
  - Client sends: `{ "type":"hb" }`
  - Server may reply: `{ "type":"hb-ack" }` and refreshes TTL.

- Kill a session (admin or workstation):
  - Command: `curl -i -X DELETE http://localhost:3001/api/session/<sessionId>`
  - Expected status: `HTTP/1.1 204 No Content`
  - Active peers receive and are closed: `{ "type":"session-killed" }`

- Health check:
  - Command: `curl -s http://localhost:3001/health`
  - Expected output: `{ "ok": true }`

## Mobile Client (phone)

- Obtain QR payload from workstation’s `POST /api/register` response (`qrPayload`):
  - Example: `{ "u":"ws://localhost:3001/ws", "s":"<sessionId>", "t":"<token>" }`

- Connect to WebSocket URL `u` and identify:
  - First client message: `{ "type":"hello", "s":"<sessionId>", "t":"<token>", "r":"phone" }`
  - Expected server response: `{ "type":"hello-ack", "sessionId":"<sessionId>" }`
  - When the workstation joins, you receive: `{ "type":"peer-joined", "role":"workstation" }`

- Receive text payloads (from workstation):
  - Example incoming frame:
    - `{ "type":"frame", "sid":"<sessionId>", "fromRole":"workstation", "at":<unix_ts>, "frame":"hi-from-workstation", "b64":false }`

- Send text payloads (to workstation):
  - Client sends plain text (e.g., `"hi-from-phone"`).
  - Workstation receives wrapped relay frame with `fromRole:"phone"`.

- Heartbeat: send `{ "type":"hb" }` periodically; expect optional `{ "type":"hb-ack" }`.

- Disconnects and kills:
  - When the workstation disconnects you may receive: `{ "type":"peer-left", "role":"workstation" }`.
  - When the session is explicitly killed: `{ "type":"session-killed" }`, then the socket closes.

## Quick WebSocket Demo (websocat)

- 0) Get credentials (sid, tok, ws):
  - `curl -s -X POST http://localhost:3001/api/register | jq -r '.sessionId,.token,.ws'`
- 1) Terminal A (workstation):
  - `websocat -t ws://localhost:3001/ws`
  - Send: `{"type":"hello","s":"<sid>","t":"<tok>","r":"workstation"}`
  - Expect: `{"type":"hello-ack","sessionId":"<sid>"}`
- 2) Terminal B (phone):
  - `websocat -t ws://localhost:3001/ws`
  - Send: `{"type":"hello","s":"<sid>","t":"<tok>","r":"phone"}`
  - Expect on both terminals: `{"type":"peer-joined","role":"..."}`
- 3) Send plain text from B (phone):
  - Type: `hi-from-phone`
  - A (workstation) sees: `{"type":"frame",...,"fromRole":"phone","frame":"hi-from-phone","b64":false}`
- 4) Heartbeat from either side when idle:
  - Type: `{"type":"hb"}` (may see `{"type":"hb-ack"}`)
- 5) Kill from HTTP:
  - `curl -i -X DELETE http://localhost:3001/api/session/<sid>` → both terminals see `{"type":"session-killed"}` then close

## Python One-Liners (WS steps)

Requires: Python 3, `pip install requests websockets`.

- Register (get sid, tok, ws):
  - `python -c 'import requests,json;d=requests.post("http://localhost:3001/api/register").json();print(json.dumps(d,indent=2))'`

- Workstation: connect → hello → ack → send a text frame:
  - `python -c 'import asyncio,websockets,json;async def main():\n ws=await websockets.connect("WS");\n await ws.send(json.dumps({"type":"hello","s":"SID","t":"TOK","r":"workstation"}));\n print(await ws.recv());\n await ws.send("hi-from-workstation");\n await asyncio.sleep(0.2);\n await ws.close();\n\nimport asyncio as _;_.run(main())'`

- Phone: connect → hello → ack → receive one frame → send reply:
  - `python -c 'import asyncio,websockets,json;async def main():\n ws=await websockets.connect("WS");\n await ws.send(json.dumps({"type":"hello","s":"SID","t":"TOK","r":"phone"}));\n print(await ws.recv());\n msg=await ws.recv();print(msg);\n await ws.send("hi-from-phone");\n await asyncio.sleep(0.2);\n await ws.close();\n\nimport asyncio as _;_.run(main())'`

- Heartbeat (either role): connect → hello → send hb:
  - `python -c 'import asyncio,websockets,json;async def main():\n ws=await websockets.connect("WS");\n await ws.send(json.dumps({"type":"hello","s":"SID","t":"TOK","r":"workstation"}));\n await ws.recv();\n await ws.send(json.dumps({"type":"hb"}));\n print(await ws.recv());\n await ws.close();\n\nimport asyncio as _;_.run(main())'`

## Under The Hood (brief)

- Transport: WebSocket; text and binary frames supported. Binary is base64-encoded in relay frames with `b64:true`.
- Roles: exactly two roles per session: `workstation` and `phone`. Frames are relayed only to the opposite role.
- Session lifecycle: `POST /api/register` issues `{sessionId, token}` and QR payload `{u,s,t}`. Session TTL (`SESSION_IDLE_SECS`, default 7200s) refreshes on hello, frames, and heartbeats.
- Routing: Server wraps client frames as `{type:"frame", sid, fromRole, at, frame, b64}` and publishes on Redis channel `ch:<sid>`. Each WebSocket subscribes and forwards only messages from the opposite role. No backfill/persistence.
- Control signals: Join/leave are published as `{type:"peer-joined|peer-left", role}`. Kills publish `{type:"session-killed"}` and also use an in-process broadcast to close sockets promptly.
- Health: `GET /health` returns `{ "ok": true }` for readiness checks.

Notes
- curl examples cover HTTP endpoints; WebSocket messaging examples show the exact JSON frames exchanged once connected.
- Environment: `PORT` (3001), `REDIS_URL` (redis://127.0.0.1:6379), `PUBLIC_WS_URL` (ws://localhost:PORT/ws), `SESSION_IDLE_SECS` (7200), `HEARTBEAT_INTERVAL_SECS` (30).

## Minimal Demo Pipeline

- Run: `./relay/run-demo.sh`
- What it does:
  - Starts Redis (if needed)
  - Builds and launches the server on an isolated port
  - Runs a tiny Rust demo that: registers a session, connects workstation and phone websockets, exchanges a message both ways, sends a heartbeat, deletes the session, and observes shutdown
- Expect logs like:
  - `[workstation] -> hello` then `<- {"type":"hello-ack",...}`
  - `[phone] -> hello` then `<- {"type":"hello-ack",...}`
  - `[workstation] -> hello-from-workstation` and `[phone] <- frame ok`
  - `[phone] -> hello-from-phone` and `[workstation] <- frame ok`
  - `DELETE /api/session/<sid>` then `session-killed` notifications
  - Correlated app messages: demo sends JSON frames with `id` and `replyTo` to show request/response across peers. Set `DEMO_SEED=myrun` to control the ids like `myrun-p1`, `myrun-w1`.

## Real-World Setup

- Server: deploy the relay server behind HTTPS on a public domain (e.g., `wss://relay.example.com/ws`). Use your infra’s port forwarding / reverse proxy and set `PUBLIC_WS_URL` accordingly.
- Phone app: embed `relay-client-mobile` and, after scanning a QR payload `{u,s,t}`, call `connect_with_qr(...)`. Send app JSON as plain text; receive peer frames via the `on_message` callback.
- Workstation app: call `POST /api/register` on the server URL, show the QR to the user (or otherwise share `{u,s,t}`), then connect to `ws` and send `hello` with role `workstation`. Send/receive app JSON as plain text; correlate with `id/replyTo` if desired.
