# CodeWalk

The overarching goal of this project is to allow knowledge workers to spend as much productive time outside of their house by interfacing with their machine at home via voice. With the rise of agents (and computer using agents (CUAs)), voice interfaces are becoming increasingly viable. What is missing right now is the proper stack and interfaces built by people that actually use them. 

Just start this app on your computer, install the app for your phone, link them up via a QR code scan, and you will be having access to your work station while out and about. The end goal is to be able to have a conversation with an orchestrator agent that will help you spec things out, and give you real time narration of the progress of different agents. 

Over time, we will add means of inspectability: 
- Showing recordings of the app you're building
- Selective inspection, like showing code snippets
- Verifier agents and heavy QA testing pipelines

Manual Test (multiple terminals)

1) Prepare `.env` at repo root with `RELAY_WS_URL`, `RELAY_SESSION_ID`, `RELAY_TOKEN` and your groq api key.

2) Terminal A — Relay server
```
   cd relay/server
   cargo run --release --bin relay-server
```
3) Terminal B — Workstation (TUI)
```
   cargo run -p orchestrator --bin codewalk
```
4) Terminal C — App
```
   cd apps/VoiceRelaySwiftUI
   ./run-sim.sh
```
5) Send a message from the app

   Type text and press Send. The app shows “Ack: received”. The TUI prints a `RELAY> user_text: ...` line.

