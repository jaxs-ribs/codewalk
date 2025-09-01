VoiceRelay SwiftUI (iOS)

This is a native Swift/SwiftUI rewrite of the VoiceRelay mobile client. It preserves the original functionality with a cleaner, modern UI:

- Health check to your relay server
- WebSocket connect/hello/heartbeats
- Send text messages to the relay (`user_text`)
- Press-to-record voice → upload to Groq Whisper → send transcript to relay
- Logs request over the same WebSocket path

It does not depend on React Native. Build and run directly in Xcode.


Requirements
- Xcode 15+
- iOS 15+ Simulator or device
- A running relay server (see repo’s `relay/server`)
- Top-level `.env` with:
  - `GROQ_API_KEY`
  - `RELAY_WS_URL` (e.g., `ws://127.0.0.1:3001/ws` or base URL; the app normalizes it)
  - `RELAY_SESSION_ID`
  - `RELAY_TOKEN`


Project setup
1) Create the Xcode project (one-time)
   - In Xcode: File → New → Project… → iOS → App
   - Product Name: VoiceRelaySwiftUI
   - Interface: SwiftUI; Language: Swift
   - Save inside repo at `apps/VoiceRelaySwiftUI/`

2) Add the provided source files
   - Drag these files into the app target (tick “Copy items if needed”):
     - `apps/VoiceRelaySwiftUI/Sources/VoiceRelaySwiftUIApp.swift`
     - `apps/VoiceRelaySwiftUI/Sources/ContentView.swift`
     - `apps/VoiceRelaySwiftUI/Sources/EnvConfig.swift`
     - `apps/VoiceRelaySwiftUI/Sources/RelayWebSocket.swift`
     - `apps/VoiceRelaySwiftUI/Sources/Recorder.swift`
     - `apps/VoiceRelaySwiftUI/Sources/STTUploader.swift`

3) Configure Info.plist (or replace with the provided one)
   - Add the following keys (or use the provided `apps/VoiceRelaySwiftUI/Info.plist`):
     - `NSMicrophoneUsageDescription` = "We use the microphone to capture voice commands for transcription."
     - `NSAppTransportSecurity` →
       - `NSAllowsLocalNetworking` = YES
       - `NSAllowsArbitraryLoads` = YES (dev only; remove when you host relay over TLS)
       - `NSExceptionDomains` → `api.groq.com` (TLS min v1.2)

4) Bundle .env (for simulator convenience)
   - Add a Run Script Build Phase (after “Compile Sources”):
     - Script:
       
       cp -f "${PROJECT_DIR}/../../.env" "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/.env" || true
       
     - This makes the app load the top-level `.env` automatically when built from this repo.

5) Build & run on Simulator
   - Start relay:
     - Terminal A:
       - `cd relay/server`
       - `cargo run --release --bin relay-server`
   - Ensure `.env` is configured at the repo root (same values used by server & app)
   - In Xcode: select a Simulator → Run.


Usage
- The app reads `.env` from the app bundle. Config fields are not shown in the UI (no secrets on screen). For dev, edit the repo `.env` and re-run `./run-sim.sh`.
- On launch (and when returning to foreground) the app automatically connects to the relay and sends `hello`.
- Use the bottom toolbar to type a message and Send. The input disables until the socket is open.
- Tap Rec to start; tap Stop to upload to Groq STT and auto-send the transcript. The recording/transcription flow is a typed state machine to avoid stuck states.
- Use the toolbar action to fetch Logs. A Disconnect action is available for debugging.
- Debug details (state/last events/close codes) are available via the “Show details” toggle.


Troubleshooting
- Microphone permission denied: the app will show a prompt to open Settings.
- Empty transcript: check the Upload/Transcribe logs; try a longer utterance and minimal background noise. The app records WAV 16kHz mono (or M4A fallback) and uploads via URLSession.
- Can’t connect to relay on Simulator: ensure you’re using `ws://127.0.0.1:3001/ws` (not `localhost`). The run script injects ATS allowances for local dev automatically.

Terminal-only quick run

Run everything from the terminal without opening Xcode.

Prereqs:
- Xcode installed and selected: `xcode-select -p`
- Homebrew tools: `brew install xcodegen`

Steps:
- Terminal A — start relay server
  - `cd relay/server`
  - `cargo run --release --bin relay-server`

- Terminal B — build and launch the iOS app on Simulator
  - `cd apps/VoiceRelaySwiftUI`
  - `chmod +x run-sim.sh` (first time only)
  - `./run-sim.sh`

What the script does:
- Generates the Xcode project from `project.yml` via XcodeGen
- Copies the repo’s top-level `.env` into the built `.app` bundle
- Boots (or reuses) an iOS Simulator (defaults to iPhone 16 Pro if available)
- Builds the app into a local DerivedData directory
- Installs and launches the app on the Simulator
- Adds microphone privacy text and ATS overrides for local networking to the built Info.plist

Environment
- The app reads `.env` at runtime from the app bundle (copied by build).
- Edit the repo’s `.env` and rerun `./run-sim.sh` to pick up changes.
