# Context Auto-Loading System

## Overview

Artifacts and research results are now automatically loaded into conversation context **silently** (without TTS), enabling the agent to answer questions about them naturally.

## What Gets Auto-Loaded

### 1. Artifacts (after write/edit)
- ✅ `description.md` - After write or edit
- ✅ `phasing.md` - After write, edit, split, or merge
- Format: `[Context: Updated {filename}]\n\n{full content}`

### 2. Research Results (after search)
- ✅ Perplexity search - Raw results before summarization
- ✅ Brave search - Raw results
- ✅ Deep research - Full research data
- Format: `[Context: Search results for '{query}']\n\n{results}`

## How It Works

### Flow Example: Writing Phasing

```
1. User: "Write phasing for a todo app"
2. Agent generates phasing.md
3. Agent writes to disk
4. Agent auto-loads into context:
   conversationContext.addSilentContextMessage(phasingContent, type: "Updated phasing.md")
5. Agent speaks: "Phasing written"
6. User hears: "Phasing written" (clean, short)
7. Agent has full phasing in context (not spoken)

8. User: "How many phases?"
9. Agent reads from context, counts: 4 phases
10. Agent speaks: "There are 4 phases"
```

### Flow Example: Research

```
1. User: "Research React hooks"
2. Agent calls Perplexity API
3. Agent receives raw results (detailed)
4. Agent loads into context:
   conversationContext.addSilentContextMessage(rawResults, type: "Search results for 'React hooks'")
5. Agent distills summary for TTS
6. Agent speaks: "React hooks let you use state in function components..." (clean summary)
7. User hears summary
8. Agent has full research in context

9. User: "What were the specific examples mentioned?"
10. Agent references full context
11. Agent quotes details from raw research
```

## Implementation Details

### Phase 1: Silent Context Injection ✅

**Added to `ConversationContext`:**
```swift
func addSilentContextMessage(_ content: String, type: String)
static func isContextMessage(_ content: String) -> Bool
```

**Updated `VoiceOutputManager`:**
- Filters out `[Context:` messages from TTS
- Logs skip for debugging

### Phase 2: Artifact Auto-Loading ✅

**Updated `ArtifactActionHandler`:**
- After `writeArtifact()` success → `loadArtifactIntoContext()`
- After `editPhase()` success → load updated phasing
- After `splitPhase()` success → load updated phasing
- After `mergePhases()` success → load updated phasing
- After full artifact regeneration → load updated content

### Phase 3: Research Auto-Loading ✅

**Updated `SearchActionHandler`:**
- After Perplexity search → load raw `summary` into context
- After Brave search → load raw `summary` into context
- User hears cleaned/distilled version via TTS
- Agent has full details in context

### Phase 4: System Prompt Guidance ✅

**Updated `ContentGenerator` conversational prompt:**
```
CONTEXT-LOADED DOCUMENTS:
After creating/editing artifacts or performing research,
the full content is automatically loaded with [Context: ...] markers.

When answering questions:
- Reference the most recent [Context: ...] version
- Answer directly from that content
- No need to say "let me check"

Examples:
- "How many phases?" → Count from [Context: Updated phasing.md]
- "What did research say?" → Reference [Context: Search results...]
```

## Message Format

### Context Messages
```
[Context: Updated description.md]

# Project Description

A comprehensive todo app...
```

### Regular Messages
```
I've written the phasing based on our conversation.
```

## Persistence

✅ Context messages are saved in `conversation.json`
✅ Loaded on session restore
✅ Survive app restarts
✅ Part of normal conversation history

## Token Management

**Strategy:**
- Keep ALL context messages (no pruning)
- Research results included fully
- Multiple versions of same artifact preserved
- Typical usage: ~5-10k tokens

**Why No Pruning:**
- Groq supports prompt caching
- Keeping stable conversation prefix = cache hits = token savings
- Pruning old versions would invalidate cache
- Better to keep everything and benefit from caching

**Monitoring:**
- `estimateTokenCount()` provides rough token count (1 token ≈ 4 chars)
- `getContextStats()` shows message counts and estimated tokens
- Warning logged if context exceeds 24k tokens (approaching 32k limit)

## Testing Scenarios

### Artifact Awareness
```
User: "Write description for a blog platform"
Agent: *writes, injects context*
User: "What did we just write?"
Agent: *quotes from context, not "I don't have access"*
```

### Phase Counting
```
User: "Write phasing"
Agent: *writes 4 phases, injects*
User: "How many phases?"
Agent: "There are 4 phases"
```

### Research Recall
```
User: "Research Next.js 14"
Agent: *searches, injects raw results, speaks summary*
User: "What specific features were mentioned?"
Agent: *references full context, quotes details*
```

## Benefits

1. **Natural Q&A**: Agent knows what it just wrote/researched
2. **No hallucination**: Content is actually in context
3. **Clean TTS**: User hears summaries, not full artifacts
4. **Context continuity**: Artifacts persist across conversation
5. **Session portability**: Context saves/loads with session

## Debugging

**Check if context is being injected:**
```
grep "\[Context:" artifacts/active-session/conversation.json
```

**View full conversation with context:**
```
cat artifacts/active-session/conversation.json | jq
```

**Logs to watch:**
```
Added silent context: Updated phasing.md (1234 chars)
Skipping TTS for context message
Loaded phasing.md into context (1234 chars)
```

## Complete! ✅

All 6 phases implemented:
- ✅ Phase 1: Silent context injection helpers
- ✅ Phase 2: Artifact auto-loading
- ✅ Phase 3: Research auto-loading
- ✅ Phase 4: System prompt enhancement
- ✅ Phase 5: Comprehensive testing (7 test scenarios)
- ✅ Phase 6: Token budget monitoring (no pruning to preserve cache)
