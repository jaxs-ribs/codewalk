VoiceRelay Mobile (React Native)

Minimal React Native app that connects to the relay using a single shared .env at the repo root. It shows connectivity, opens a WebSocket, and lets you send a note to the workstation.

Unified Config (.env at repo root)

Put these keys in `./.env` (no exports):

RELAY_WS_URL=ws://127.0.0.1:3001/ws
RELAY_SESSION_ID=dev-session-123
RELAY_TOKEN=dev-token-abc

The relay server pre-creates this session on startup; the app and orchestrator both read the same values.

Run

- Terminal A (Metro):

  cd apps/VoiceRelay
  npm install   # installs babel-plugin-inline-dotenv used to read ../../.env
  npm start

- Terminal B (iOS Simulator):

  cd apps/VoiceRelay
  npm run ios -- --simulator="iPhone 16 Pro"

Android Emulator (optional):

  cd apps/VoiceRelay
  npm run android

What You Should See

- Status pill shows Connected once relay is up
- Details panel displays WS, sid, tok from .env
- Typing a message and pressing Send emits a `note`; the workstation replies with `ack: received`

Troubleshooting

- Ensure relay is running and using the same .env
- If health is Disconnected, confirm RELAY_WS_URL host resolves for your simulator (iOS uses 127.0.0.1; Android uses 10.0.2.2)
- If the app shows “Health: configure RELAY_WS_URL in .env”, make sure the root .env has RELAY_* keys, then run `npm install` and restart Metro with `npm start -- --reset-cache`.
- Clear Metro cache: `npm start -- --reset-cache`
