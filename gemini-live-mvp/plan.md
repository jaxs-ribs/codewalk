# WalkCoach to Gemini Live API - Implementation Plan

## Executive Summary

We're porting the WalkCoach iOS speccer to use Gemini Live API, maintaining its core behavior: a voice-first project specification tool that listens passively, acknowledges ideas with "Noted", and generates comprehensive markdown artifacts on command.

## System Architecture Mapping

### Core Components from WalkCoach

1. **Router System Prompt** - Classifies input as directive vs conversation (VERY conservative)
2. **Description Generator Prompt** - Creates TTS-optimized project descriptions (1500-2500 chars)
3. **Phasing Generator Prompt** - Creates implementation roadmaps with testable deliverables
4. **Conversation Response Prompt** - Passive note-taker that responds "Noted" to statements
5. **Orchestrator** - Single-threaded action queue with IoGuard
6. **ArtifactManager** - Atomic file operations with backups

### Gemini Live API Constraints

- **Model**: Must use `gemini-live-2.5-flash-preview` (half-cascade) for tool support
- **Modality**: `AUDIO` only (with transcriptions enabled)
- **Tools**: Implement via `functionDeclarations` in config
- **System Prompts**: Set at connection time, can update via role:"system" turn

## Critical System Prompts to Port

### 1. Router Prompt (Intent Classification Tool)
```
DEFAULT to conversation unless there's an EXPLICIT command
Users will mostly be sharing ideas, not giving commands
Be very conservative about interpreting as directives

Only classify as directive for:
- "write description/phasing"
- "read description/phasing/phase N"
- "edit description/phasing"
- "copy description/phasing/both"
- Navigation: "next/previous phase", "stop", "repeat"
```

### 2. Passive Conversation Prompt
```
STATEMENTS → Respond ONLY "Noted"
TECHNICAL QUESTIONS → 2-3 sentence answer
YES/NO QUESTIONS → Clear yes/no + ONE sentence
BRAINSTORMING → 2-3 concrete suggestions

You're a SINK for ideas. Default to brief acknowledgments.
```

### 3. Description Generator Prompt
```
Generate 1500-2500 CHARACTER markdown
TTS-OPTIMIZED: No bullets, flowing prose, contractions
Review ENTIRE conversation history
Write like explaining to a friend on a walk
Format: # Project Description\n\n[Natural prose]
```

### 4. Phasing Generator Prompt
```
Generate 3-5 phases covering ALL features
Each phase: ONE paragraph (200-400 chars)
MUST end with "When this phase is done, you'll be able to..."
TTS-OPTIMIZED: Flowing prose, no bullets
Format: ## Phase N: [Title]\n[Paragraph with testable deliverable]
```

## Implementation Strategy

### Tool Definitions

```javascript
// Core tools matching WalkCoach ProposedActions
const tools = [{
  functionDeclarations: [
    {
      name: "write_artifact",
      description: "Write description or phasing markdown",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: { type: "STRING", enum: ["description", "phasing"] },
          content: { type: "STRING", description: "Full markdown content" }
        },
        required: ["artifact_type", "content"]
      }
    },
    {
      name: "read_artifact",
      description: "Read description, phasing, or specific phase",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: { type: "STRING", enum: ["description", "phasing", "phase"] },
          phase_number: { type: "INTEGER", description: "Phase number if reading specific phase" }
        },
        required: ["artifact_type"]
      }
    },
    {
      name: "edit_artifact",
      description: "Edit existing artifacts",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: { type: "STRING", enum: ["description", "phasing"] },
          edit_content: { type: "STRING" },
          phase_number: { type: "INTEGER", description: "Phase to edit if editing phasing" }
        },
        required: ["artifact_type", "edit_content"]
      }
    },
    {
      name: "route_intent",
      description: "Classify user input as directive or conversation",
      parameters: {
        type: "OBJECT",
        properties: {
          intent: { type: "STRING", enum: ["directive", "conversation"] },
          action: { type: "STRING" },
          reasoning: { type: "STRING" }
        },
        required: ["intent"]
      }
    }
  ]
}];
```

### State Management

- **Conversation History**: Array of last 100 exchanges
- **Current Context**: Track what artifact we're working on
- **IoGuard**: Boolean flag preventing concurrent operations
- **Last Response**: Cache for "repeat last" functionality

## Phasing Plan

### Phase 1: Basic Tool Infrastructure
**Goal**: Gemini can call tools and we can handle responses

First, we'll set up the foundation for tool calling with Gemini Live API. We'll define our tool schemas for write_artifact, read_artifact, and route_intent, then implement the message handler that detects toolCall messages and sends back toolResponse. We'll use the half-cascade model to ensure tool support and add comprehensive logging to see exactly what Gemini is trying to do. When this phase is done, you'll be able to say "write a test file" and see Gemini attempt to call the write_artifact tool with the console showing the full tool call details.

**Test**:
```bash
npm run speccer
# Say: "Write a test description"
# Expected: Console shows tool call attempt with artifact_type:"description"
```

### Phase 2: Router Implementation
**Goal**: User input correctly classified as directive vs conversation

Next, we'll implement the router that determines user intent. We'll port the conservative router prompt from WalkCoach that defaults everything to conversation unless there's an explicit command. The router will use a special tool call to classify intent, distinguishing between directives like "write the description" and conversational statements like "I want blue buttons". We'll add detailed logging showing the classification reasoning. When this phase is done, you'll be able to speak naturally and see whether your input was routed as a directive or conversation.

**Test**:
```bash
npm run speccer
# Say: "I think it should have user accounts"
# Expected: Console shows "CONVERSATION: I think it should have user accounts"
# Say: "Write the description"
# Expected: Console shows "DIRECTIVE: write_description"
```

### Phase 3: Artifact Writing
**Goal**: "Write description" creates actual markdown files

Then we'll implement the artifact writing system with atomic file operations. We'll create an artifacts directory structure, implement the description generator prompt that creates TTS-optimized markdown, add atomic writes using temp files to prevent corruption, and include automatic timestamped backups. The system will synthesize the entire conversation history into comprehensive artifacts. When this phase is done, you'll be able to share several ideas then say "write the description" and find a well-formatted description.md file in the artifacts folder.

**Test**:
```bash
npm run speccer
# Say: "I want to build a meditation app with breathing exercises"
# Say: "It should track user progress"
# Say: "Write the description"
# Expected: artifacts/description.md created with natural prose
# Check: File reads naturally when spoken aloud
```

### Phase 4: Passive Conversation Mode
**Goal**: Assistant responds appropriately based on input type

After that we'll implement the passive note-taking personality. We'll port the conversation prompt that responds "Noted" to statements, gives brief technical answers to questions, and provides yes/no responses with single clarifications. This makes the assistant feel like a passive listener rather than an eager collaborator. The system will analyze each input to determine the appropriate response style. When this phase is done, you'll hear "Noted" for statements and get concise answers for questions.

**Test**:
```bash
npm run speccer
# Say: "The app needs a dark mode"
# Expected: Hear "Noted"
# Say: "Should I use React Native?"
# Expected: Hear "Yes, React Native would work well for cross-platform development"
```

### Phase 5: Phasing Generation
**Goal**: Generate implementation roadmaps with testable deliverables

Next we'll add the phasing generator that creates actionable implementation plans. We'll port the phasing prompt that generates three to five phases each ending with "When this phase is done, you'll be able to...", ensure it reviews the entire conversation to extract all features, and format output as flowing paragraphs perfect for TTS. Each phase will have a clear, verifiable outcome. When this phase is done, you'll be able to describe your app features then say "write the phasing" and get a concrete implementation roadmap.

**Test**:
```bash
npm run speccer
# Say: "The app needs user auth, a dashboard, and data sync"
# Say: "Write the phasing"
# Expected: artifacts/phasing.md with 3-5 phases
# Check: Each phase ends with testable deliverable
```

### Phase 6: Artifact Reading
**Goal**: Read back written artifacts with natural flow

Then we'll implement artifact reading with TTS optimization. The system will read markdown files with natural pauses, handle phase navigation commands like "read phase 2", chunk content for better comprehension, and track current reading position. We'll add support for "next", "previous", and "stop" commands during reading. When this phase is done, you'll be able to say "read the description" and hear your spec read back naturally.

**Test**:
```bash
npm run speccer
# First write some artifacts using previous phases
# Say: "Read the description"
# Expected: Hear description read with natural flow
# Say: "Read phase 2"
# Expected: Jump to and read specific phase
```

### Phase 7: Edit Operations
**Goal**: Modify existing artifacts with targeted edits

After that we'll add intelligent edit capabilities. We'll implement "edit description to add..." for appending content, "change phase N to..." for replacing specific sections, and maintain document structure during edits. The system will use conversation context to make appropriate modifications. When this phase is done, you'll be able to refine your artifacts with voice commands.

**Test**:
```bash
npm run speccer
# Ensure artifacts exist from previous phases
# Say: "Edit the description to add performance requirements"
# Expected: description.md updated with new content appended
# Say: "Change phase 1 to focus on database setup"
# Expected: Phase 1 replaced while others remain
```

### Phase 8: Conversation Memory & Context
**Goal**: Maintain full session context for comprehensive artifacts

Next we'll implement robust conversation tracking. We'll store the last 100 exchanges for full context, pass entire history when generating artifacts, implement "repeat last" functionality, and add "what did I just say" recognition. This ensures artifacts capture everything discussed across long sessions. When this phase is done, your artifacts will comprehensively reflect entire conversations, not just recent messages.

**Test**:
```bash
npm run speccer
# Have a 5-turn conversation about features
# Say: "What did I just say?"
# Expected: Accurate recall of recent statement
# Say: "Write the description"
# Expected: Description includes ALL mentioned features
```

### Phase 9: Audio State Feedback
**Goal**: Clear audio announcements of system state

Then we'll add voice feedback for all operations. The system will announce "Writing description now..." before file operations, say "Reading phase two..." before reading sections, confirm "Done" after operations complete, and provide audio feedback for errors. This ensures you know what's happening without looking at the screen. When this phase is done, every action will have clear audio confirmation.

**Test**:
```bash
npm run speccer
# Say: "Write the description"
# Expected: Hear "Writing description now..." then "Done"
# Say: "Read phase 2"
# Expected: Hear "Reading phase two..." before content
```

### Phase 10: Export & Navigation
**Goal**: Advanced navigation and clipboard export

After that we'll add navigation and export features. We'll implement "copy description/phasing/both" for clipboard operations, "next/previous phase" during reading, session state persistence, and quick navigation commands. The system will format exports with proper markdown structure. When this phase is done, you'll be able to navigate smoothly through artifacts and export them for use elsewhere.

**Test**:
```bash
npm run speccer
# Ensure artifacts exist
# Say: "Copy both"
# Expected: Console shows "Copied description and phasing to clipboard"
# Paste in text editor to verify formatting
# Say: "Read the phasing" then "Next" during reading
# Expected: Advances to next phase
```

### Phase 11: Production Robustness
**Goal**: Handle errors, reconnections, and long sessions

Finally we'll add production-grade reliability. This includes automatic retry for network failures, session persistence across reconnects, graceful handling of API limits, and state recovery after crashes. We'll ensure the system can handle thirty-minute walking sessions while maintaining context. When this phase is done, you'll have a robust speccer that handles real-world conditions.

**Test**:
```bash
npm run speccer
# Simulate network interruption (disconnect WiFi briefly)
# Expected: Graceful recovery with context maintained
# Have a 20-minute conversation with multiple artifacts
# Expected: All context preserved, artifacts comprehensive
```

### Phase 12: Polish & Optimization
**Goal**: Production-ready walking speccer

The final phase adds polish and optimizations. We'll tune prompts specifically for Gemini's strengths, add voice configuration options, implement chunked reading with optimal pauses, and optimize for lowest latency. We'll ensure the system feels responsive and natural during walking sessions. When complete, you'll have a production-ready speccer matching WalkCoach's capabilities.

**Test**:
```bash
npm run speccer
# Full walkthrough: describe app → write description → add features → write phasing → edit → export
# Expected: Smooth, natural flow with no awkward pauses
# Verify: All artifacts properly formatted for TTS
```

## Success Criteria

- [ ] Router correctly classifies 95%+ of inputs (conservative bias toward conversation)
- [ ] "Noted" response for statements, brief responses for questions
- [ ] Artifacts are TTS-optimized (no bullets, flowing prose)
- [ ] Descriptions capture entire conversation context
- [ ] Phasing includes testable deliverables
- [ ] Single-threaded execution prevents race conditions
- [ ] Audio feedback for all operations
- [ ] 30+ minute sessions maintain full context
- [ ] Graceful recovery from network issues