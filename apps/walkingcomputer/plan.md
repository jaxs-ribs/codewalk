# Walking Computer - Critical Issues and Fix Plan

## Session Context
Date: 2025-09-28
App: Walking Computer (iOS voice-first speccer)
Issue: Multiple critical bugs identified during testing session

## Identified Issues from Test Session Logs

### 1. Phase Content Inconsistency
**Evidence from logs:**
```
[20:21:20.898] Executing action: readSpecificPhase(1)
## Phase 1: Basic iOS App Shell
So first we'll create a minimal iOS app with just a single view controller...

[20:22:29.092] Executing action: readSpecificPhase(1)
## Phase 1: Basic Recording
So first we'll get the iOS app to record your voice using the built-in AVAudioEngine...

[User at 20:22:17.305] 💬 AI: 1. Phase 1 – Core iOS Skeleton with Groq Speech-to-Text
```

**Problem**: The same phase (Phase 1) returns completely different content on each read
**Root Cause**: The LLM is regenerating phase content instead of reading from the stored phasing.md file
**Impact**: Users can't rely on consistent artifact content

### 2. Search Commands Not Executing
**Evidence from logs:**
```
[20:22:56.914] Router: Intent: directive, Action: search("prior art existing solutions...")
[20:22:56.918] Executing action: search("prior art existing solutions...")
[20:23:04.140] Search successful, summary: 603 chars
```
But then later:
```
[20:23:35.042] Executing action: conversation("that. Yeah, look it up.")
[20:23:35.655] 💬 AI: After searching the web, I found no exact match for an iOS app...

[20:23:42.780] Executing action: conversation("Search the web with that query.")
[20:23:43.434] 💬 AI: After searching the web, I found no exact match for an iOS app...
```

**Problem**: Later search requests return instant identical responses without actual search logs
**Root Cause**: The search is being handled by conversation instead of actually executing
**Impact**: Users get fake search results

### 3. Router Misclassification
**Evidence from logs:**
```
[20:23:41.793] 👤 User: Search the web with that query.
[20:23:42.778] Router: Raw LLM response: {
    "intent": "conversation",
    "action": {
        "action": "conversation",
        "content": "Search the web with that query."
    },
    "reasoning": "No specific search query provided - 'that query' is undefined without context"
}
```

**Problem**: Clear search directive classified as conversation
**Root Cause**: Router loses context between exchanges
**Impact**: Commands fail to execute

### 4. Artifacts Still Writing to Wrong Directory
**Evidence from filesystem:**
```bash
# At 20:22 in the session
/Users/fresh/Documents/codewalk/apps/walkcoach/artifacts/
-rw-r--r--@ 1 lucbaracat  staff  2210 Sep 28 20:20 description.md
-rw-r--r--@ 1 lucbaracat  staff  3283 Sep 28 20:22 phasing.md

/Users/fresh/Documents/codewalk/apps/walkingcomputer/artifacts/
-rw-r--r--@ 1 lucbaracat  staff  1999 Sep 28 18:46 description.md  # Old
-rw-r--r--@ 1 lucbaracat  staff  3594 Sep 28 19:57 phasing.md      # Old
```

**Problem**: New artifacts being written to old walkcoach directory
**Root Cause**: App was running with old compiled binary despite source code changes
**Impact**: Artifacts in wrong location

### 5. Context Loss Between Exchanges
**Evidence from logs:**
```
[20:23:25.002] 💬 AI: Search query: "voice-first iOS app Groq speech-to-text..."
[20:23:34.578] 👤 User: that. Yeah, look it up.
[20:23:35.039] Router: Action: conversation("that. Yeah, look it up.")
```

**Problem**: "that" reference not understood despite just mentioning the query
**Root Cause**: Router not receiving conversation history
**Impact**: Natural conversation flow broken

## Comprehensive Fix Plan

### Priority 1: Fix Artifact Directory (CRITICAL)
**Files to modify:** `Sources/ArtifactManager.swift`
```swift
// Line 13 - Verify this is correct:
let projectPath = "/Users/fresh/Documents/codewalk/apps/walkingcomputer"
```
**Steps:**
1. Verify path in ArtifactManager.swift
2. Clean build: `rm -rf build/DerivedData`
3. Rebuild: `xcodegen generate && xcodebuild...`
4. Test: Write new artifact and check location

### Priority 2: Fix Phase Reading Consistency
**Files to modify:** `Sources/Orchestrator.swift`
**Issue:** Look for where `readSpecificPhase` is implemented
**Fix needed:**
```swift
case .readSpecificPhase(let phaseNumber):
    // MUST use ArtifactManager.readPhase() not AssistantClient
    if let phaseContent = artifactManager.readPhase(from: "phasing.md", phaseNumber: phaseNumber) {
        // Return the actual file content
        lastResponse = phaseContent
    }
```

### Priority 3: Fix Search Execution
**Files to modify:** `Sources/Orchestrator.swift`, `Sources/Router.swift`
**Issue:** Search action being short-circuited
**Fix needed:**
1. Ensure SearchService is actually called
2. Add proper await for search results
3. Store last search query for "that" references
```swift
private var lastSearchQuery: String?

case .search(let query):
    lastSearchQuery = query
    let results = await searchService.search(query)
    // Actually return results
```

### Priority 4: Improve Router Intelligence
**Files to modify:** `Sources/Router.swift`
**Issue:** Router doesn't understand context
**Fix needed:**
```swift
func route(transcript: String, conversationHistory: [String]) async throws -> RouterResponse {
    // Pass history to LLM for context
    let prompt = """
    Recent conversation:
    \(conversationHistory.suffix(3).joined(separator: "\n"))

    Current input: \(transcript)
    Last search query: \(orchestrator.lastSearchQuery ?? "none")
    """
}
```

### Priority 5: Add Conversation Memory
**Files to modify:** `Sources/Orchestrator.swift`
**Add state tracking:**
```swift
class Orchestrator {
    private var lastSearchQuery: String?
    private var lastArtifactMentioned: String?  // "description" or "phasing"
    private var conversationHistory: [String] = []

    func addUserTranscript(_ transcript: String) {
        conversationHistory.append("User: \(transcript)")
        if conversationHistory.count > 10 {
            conversationHistory.removeFirst()
        }
    }
}
```

### Priority 6: Add Verification & Logging
**Files to modify:** `Sources/ArtifactManager.swift`
**Add verification:**
```swift
func safeWrite(filename: String, content: String) -> Bool {
    // Log full path
    log("Writing to: \(artifactsPath.path)/\(filename)", category: .artifacts)

    // Add checksum
    let checksum = content.hash
    log("Content checksum: \(checksum)", category: .artifacts)

    // Write file
    // ...
}
```

## Testing Protocol

### Test 1: Artifact Directory
```bash
1. ./run-sim.sh
2. Say "write the description"
3. Check: ls -la /Users/fresh/Documents/codewalk/apps/walkingcomputer/artifacts/
4. Should see new description.md with current timestamp
```

### Test 2: Phase Consistency
```bash
1. Say "write the phasing"
2. Say "read phase 1"
3. Note the content
4. Say "read phase 1" again
5. Content should be IDENTICAL
```

### Test 3: Search Execution
```bash
1. Say "search for iOS voice recording libraries"
2. Should see SearchService logs
3. Say "search for that again"
4. Should execute search with same query
```

### Test 4: Context Preservation
```bash
1. Say "I want to build a game"
2. Say "write the description about it"
3. Should understand "it" refers to the game
```

## Session Recovery Notes
- App renamed from WalkCoach to Walking Computer
- Using Groq STT (with Avalon as option via --avalon-stt flag)
- Using Kimi K2 model for LLM
- TTS options: iOS native (default), Groq (--groq-tts), ElevenLabs (--elevenlabs)
- Clean, colored logging without file I/O for performance
- Artifacts stored in project directory for visibility

## Next Steps
1. Implement Priority 1 (artifact directory) first - it's critical
2. Test after each priority implementation
3. Keep this plan.md updated with fixes applied
4. Consider adding integration tests for each issue