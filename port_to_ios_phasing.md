# iOS Port Phasing

## Phase 0 — Template Fork with UI Preservation
Create a new folder `apps/walkcoach` by copying the entire VoiceRelaySwiftUI template. Keep the exact same folder structure: project.yml, run-sim.sh, run-sim-with-logs.sh, Sources/, and Info.plist. Keep ALL UI code intact including the glassmorphic design, animations, and four-state visual system. Update project.yml to change app name to WalkCoach and bundle ID to com.example.walkcoach. Remove only the WebSocket relay backend, log summarizer, and ElevenLabs TTS code. Test by running `cd apps/walkcoach && ./run-sim.sh` and verifying the UI looks identical to the original. If the app launches with the same visual design and record button animations work, Phase 0 is complete.

## Phase 1 — Recording Pipeline with UI States
Use the existing four-state UI system exactly as is. The states are: STTState.idle (blue record button), STTState.recording (red pulsing button), STTState.uploading (processing spinner), and display result (text appears). Wire the existing Recorder class without changes. The UI state transitions must match the original template exactly. Test by pressing record and seeing the button turn red with pulse animation, then releasing to see the spinner. If all four visual states display correctly in sequence, Phase 1 is complete.

## Phase 2 — Groq Transcription with Processing State
Keep the existing STTUploader code unchanged. When recording ends, the UI must show the processing spinner (STTState.uploading) while sending to Groq. Display the transcript in the same text area where WebSocket messages appeared. The UI flow is: recording (red) → processing (spinner) → transcript displayed → idle (blue). Test by saying "Hello world" and watching all state transitions. If the processing spinner appears during upload and transcript shows in the correct text area, Phase 2 is complete.

## Phase 3 — Intent Router
Port the Router struct from Rust to Swift. Send transcripts to Groq Kimi K2 with the same system prompt. Parse the JSON response into Swift enums matching Intent and ProposedAction. Test by saying "write the description" and seeing Intent.directive with action WriteDescription in logs. If five different commands route correctly, Phase 3 is complete.

## Phase 4 — State Orchestrator
Create an Orchestrator class as @StateObject managing the action queue. Port the state machine logic: Idle, Conversing, Executing. Process intents sequentially with IoGuard equivalent (disable UI during execution). Test by saying "read the description" and seeing state transitions in order. If the queue processes without race conditions, Phase 4 is complete.

## Phase 5 — Artifact Management
Implement artifact reading and writing in the Documents directory. Create artifacts/description.md and artifacts/phasing.md paths. Port the safe_read and safe_write functions with atomic operations. Test by saying "write the description" then checking the file exists with content. If both artifacts can be written and read back, Phase 5 is complete.

## Phase 6 — Assistant Integration
Add the AssistantClient calling Groq Kimi K2 for conversational responses. Include conversation history in requests. Store the last 20 exchanges in memory. Test by having a three-turn conversation about a project. If the assistant remembers context across turns, Phase 6 is complete.

## Phase 7 — iOS TTS Playback
Use AVSpeechSynthesizer for text-to-speech instead of the macOS `say` command. Configure voice for walking pace (150-180 words per minute). Make TTS interruptible when pressing record. Test by saying "read the phasing" and interrupting mid-sentence. If TTS stops immediately and recording starts, Phase 7 is complete.

## Phase 8 — Content Generator
Port the ContentGenerator with TTS_SYSTEM_PROMPT from Rust. Generate artifacts using conversation history as context. Implement phase-specific editing that preserves other phases. Test by saying "change phase 2 to focus on testing" and checking only that phase changed. If edits preserve surrounding content, Phase 8 is complete.

## Phase 9 — Network Resilience
Add retry logic for all Groq API calls with exponential backoff. Fall back to generic responses on network failure. Cache the last successful response for repeat commands. Test by enabling airplane mode mid-conversation. If the app shows "I understand" instead of crashing, Phase 9 is complete.

## Phase 10 — Copy to Clipboard Buttons
Add two glassmorphic buttons below the main UI: "Copy Description" and "Copy Phasing". Use the same button style as the record button with the blur effect and rounded corners. Show buttons only when the respective artifact exists (check file existence on each state change). When tapped, copy the full markdown content to UIPasteboard.general. Show a brief "Copied!" toast using the same styling. Test by generating both artifacts, tapping each button, and pasting into Notes app. If both markdown files paste correctly with formatting intact, Phase 10 is complete.

## Phase 11 — Walking Mode Polish
Add audio feedback chimes for recording start/stop using the existing sound files or system sounds. Configure background audio session for walking with screen off. The large record button is already optimized for walking. Disable auto-lock while app is active. Test by walking 500 meters using all commands without looking at screen. If you complete a full specification cycle with audio feedback working, Phase 11 is complete.

## Phase 12 — Simulator Testing Scripts
The app already has `run-sim.sh` and `run-sim-with-logs.sh` from the template. Verify they work with the new app name and bundle ID. Add debug output for state transitions, API calls, and file operations. Test by running `cd apps/walkcoach && ./run-sim-with-logs.sh` and checking app_debug.log. If every user action produces traceable logs, Phase 12 is complete.

## Phase 13 — Ship Check
Have three people walk 1km using the app to create project specifications. Measure battery drain, transcription accuracy, and artifact quality. Document any crashes or confusion. Test on iPhone 14 or newer. If battery drain stays under 5% and all three create readable artifacts, the port is ready to ship.