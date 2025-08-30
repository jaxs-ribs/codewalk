Agents and Mobile App Direction

Overview

- This repo now includes a minimal React Native app at `apps/VoiceRelay` which currently displays “Hello World.” It will evolve into a voice capture client that transcribes audio and relays results to the server and workstation components.

Planned Mobile Capabilities

- Microphone capture: Stream raw audio from the device in near real-time.
- Groq transcription: Send audio to Groq’s API for fast, accurate transcription.
- Relay integration: Forward transcripts to the relay server in this repo for downstream processing.
- Workstation comms: Use HTTP + WebSockets to coordinate with the workstation (Control Center + Orchestrator).

High-Level Flow (future)

- App captures microphone audio → streams to Groq → receives partial/final transcripts → forwards to relay server → relay publishes updates to workstation via HTTP/WebSocket → workstation orchestrates actions.

Implementation Notes (not yet implemented)

- Audio capture: evaluate libraries/native modules that support low-latency microphone streaming with pause/resume and background handling.
- Transcription: use Groq’s streaming endpoints if available; chunking and backpressure should be handled gracefully on slow networks.
- Networking: define a simple relay API for transcript ingestion (e.g., `POST /transcripts`) plus a WebSocket channel for live updates.
- Auth: plan for API keys/tokens for Groq and secure communication between app, relay, and workstation.
- Offline/edge: consider buffering and retry strategies if connectivity drops.

Where to Start

- iOS/Android build: follow `apps/VoiceRelay/README.md` for environment setup and running on simulators/emulators.
- API contracts: draft minimal REST + WS contracts between mobile → relay and relay → workstation.
- Incremental features: add microphone capture first, then wire up transcription, then delivery to relay, then workstation integration.

