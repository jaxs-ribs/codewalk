# VoiceAgent

A minimalist voice-first iOS app with a beautiful animated circle interface for voice interactions. Built with SwiftUI, designed to be a clean slate for migrating from the existing VoiceRelaySwiftUI app.

## Current Status: Phase 1 Complete ✅

### What's Been Built

#### Core Architecture
- **State Machine**: Four distinct states (Idle, Recording, Transcribing, Talking) managed by `AgentViewModel`
- **SwiftUI App**: Modern iOS 17+ app using SwiftUI and @Observable pattern
- **XcodeGen Build System**: Uses `project.yml` for project generation (no `.xcodeproj` in repo)
- **Simulator Script**: `./run-sim.sh` builds and launches app without opening Xcode

#### Visual Design
- **Fullscreen Experience**: Pure white background, no status bar, edge-to-edge display
- **Animated Circle**: 100px black/red circle with sophisticated animations
  - **Idle**: Black circle, smooth breathing (15% scale, 2.5s duration)
  - **Recording**: Red circle with glow, faster breathing (15% scale, 1.5s - 40% faster)
  - **Transcribing**: Black circle with emanating rings, same speed as recording
  - **Talking**: Black circle 1.8x size, subtle breathing (5% scale), audio-reactive movement
- **Tap Interactions**: Multi-stage spring animations with haptic feedback
  - Squash → Bounce → Settle animation sequence
  - 180° rotation on each tap
  - Color morphing between states
- **Debug Panel**: Bottom controls for testing state transitions

#### Technical Implementation

**Files Structure:**
```
VoiceAgent/
├── Sources/
│   ├── VoiceAgentApp.swift      # App entry point
│   ├── ContentView.swift        # Main UI container
│   ├── CircleView.swift         # Animated circle component
│   ├── AgentViewModel.swift     # State management
│   └── AgentState.swift         # State definitions
├── project.yml                  # XcodeGen configuration
├── Info.plist                   # iOS app configuration
├── run-sim.sh                   # Build & run script
├── .gitignore                   # Git ignore rules
└── README.md                    # This file
```

**Key Technical Decisions:**
- Using XcodeGen instead of committing `.xcodeproj` files
- Fullscreen achieved via `UIRequiresFullScreen` and `UIStatusBarHidden` in project.yml
- Animations use SwiftUI's spring physics for natural motion
- State machine pattern for clear state management
- Haptic feedback via `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`

## Development Workflow

### Running the App
```bash
cd apps/VoiceAgent
./run-sim.sh
```
This will:
1. Generate Xcode project from `project.yml`
2. Boot iPhone simulator
3. Build and install app
4. Launch automatically

### Requirements
- Xcode 15+
- iOS 17+ SDK
- XcodeGen (`brew install xcodegen`)

## Migration Plan from VoiceRelaySwiftUI

### ✅ Phase 1: Visual State Machine (COMPLETE)
**Deliverable:** Standalone app with animated circle that cycles through all states
- Implemented state machine with 4 states
- Beautiful animations with proper breathing patterns
- Debug controls for testing
- Fullscreen white background
- **Test:** Tap circle to transition between states, use debug buttons for all states

### 📱 Phase 2: Audio Recording (NEXT)
**Deliverable:** Real audio recording with visual feedback
- Port `Recorder.swift` from VoiceRelaySwiftUI
- Add microphone permissions to Info.plist
- Record audio while in Recording state
- Save recordings to temp files
- Display recording duration
- Remove debug UI for recording button (keep others for testing)
- **Test:** Tap to record 5 seconds of audio, see file saved, tap to stop

### 🎤 Phase 3: Speech-to-Text
**Deliverable:** Complete STT loop with transcription
- Port `STTUploader.swift` from VoiceRelaySwiftUI
- Port `EnvConfig.swift` for API keys
- Integrate Groq API for transcription
- Show emanating rings during transcription (already built)
- Display transcribed text temporarily on screen
- **Test:** Record speech → see rings → see transcribed text appear

### 🔊 Phase 4: Text-to-Speech
**Deliverable:** Full audio playback with visualization
- Port `ElevenLabsTTS.swift` from VoiceRelaySwiftUI
- Circle grows 2x and moves with audio (visualization already built)
- Implement audio amplitude monitoring
- Interruption on tap (stop playback → start recording)
- **Test:** Type text manually → hear speech → see audio visualization → tap to interrupt

### 🌐 Phase 5: WebSocket Integration
**Deliverable:** Complete voice agent loop
- Port `RelayWebSocket.swift` from VoiceRelaySwiftUI
- Connect to relay server
- Remove ALL debug UI elements
- Full conversation flow
- **Test:** "What's 2+2?" → hear "4" → continuous conversation

### 🚀 Phase 6: Production Ready
**Deliverable:** Polished app ready to replace current one
- Error handling & recovery states
- Network interruption handling
- Connection status indicator (subtle)
- Settings for API keys (minimal UI)
- Session management
- **Test:** 10-minute conversation without crashes, network interruption recovery

## Important Notes for Next Session

### Animation Specifications (KEEP THESE)
- **Idle**: 15% breathing, 2.5s duration
- **Recording**: 15% breathing, 1.5s duration (40% faster than idle), red with glow
- **Transcribing**: 15% breathing, 1.5s duration, with emanating rings
- **Talking**: 5% breathing (30% smaller), 2.0s duration, 1.8x base size, audio-reactive

### What Works Well
- State machine architecture is clean and extensible
- Animations are smooth and polished
- Fullscreen is properly configured
- Build system with XcodeGen works great
- Tap interactions feel premium with haptic feedback

### Next Steps Priority
1. Start Phase 2: Add `Recorder.swift` for actual audio recording
2. Keep the debug panel but only for state testing (not for triggering recording)
3. Ensure microphone permissions are properly configured
4. Test recording to temp files before moving to Phase 3

### Files to Port from VoiceRelaySwiftUI
When implementing each phase, port these files:
- Phase 2: `Recorder.swift`
- Phase 3: `STTUploader.swift`, `EnvConfig.swift`
- Phase 4: `ElevenLabsTTS.swift`
- Phase 5: `RelayWebSocket.swift`, `LogSummarizer.swift` (optional)

### Environment Variables Needed
Create `.env` file in Phase 3 with:
```
GROQ_API_KEY=your_key_here
ELEVENLABS_API_KEY=your_key_here
RELAY_URL=ws://localhost:8080
```

## Architecture Decisions

### Why Separate App?
- Clean slate without legacy code
- Focused on voice-first interaction
- Gradual migration path
- Easier to test and validate

### Why XcodeGen?
- No merge conflicts with `.xcodeproj` files
- Reproducible builds
- Clean git history
- Easy to modify project settings

### Why This Animation Approach?
- Native SwiftUI animations (no Lottie dependencies)
- Smooth 60fps performance
- Natural spring physics
- Easy to maintain and modify

## Testing Checklist

### Phase 1 Tests ✅
- [x] App launches fullscreen
- [x] Circle breathes smoothly in idle
- [x] Tap changes to recording (red, faster breathing)
- [x] Tap again returns to idle
- [x] Debug buttons trigger all states
- [x] Transcribing shows emanating rings
- [x] Talking shows larger circle with audio movement
- [x] Haptic feedback works
- [x] No black bars or status bar visible

### Phase 2 Tests (TODO)
- [ ] Microphone permission prompt appears
- [ ] Recording starts on tap
- [ ] Audio file is created
- [ ] Recording stops on second tap
- [ ] File is saved to temp directory
- [ ] Duration is displayed during recording

## Commands Reference

```bash
# Run app
cd apps/VoiceAgent
./run-sim.sh

# Clean build
rm -rf build/ VoiceAgent.xcodeproj

# Install dependencies (one-time)
brew install xcodegen

# Generate Xcode project only
xcodegen generate

# Open in Xcode (if needed)
open VoiceAgent.xcodeproj
```

---

*Last updated: Phase 1 Complete - Ready for Phase 2 Audio Recording*