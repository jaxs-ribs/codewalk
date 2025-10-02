# Walking Computer: Complete Action Reference

All actions currently available in the system (Pillar 1: Specification).

## Artifact Writing

### Write Description
Generates project description from conversation history.

**Voice commands:**
- "Write the description"
- "Create the description"
- "Generate description"

**What it does:** Creates `artifacts/description.md` with a conversational project pitch (1200-1800 chars), optimized for TTS playback.

---

### Write Phasing
Generates phasing plan from conversation history using multi-pass generation.

**Voice commands:**
- "Write the phasing"
- "Create the phasing"
- "Generate phasing"

**What it does:** Creates `artifacts/phasing.md` with 5-8 numbered phases, each with title, description, and testable definition of done. Uses two-pass AI generation (draft → critique).

**Status updates:** "Writing phasing..." → "Reviewing..." → "Phasing written."

---

### Write Both
Writes both description and phasing sequentially.

**Voice commands:**
- "Write both"
- "Write both artifacts"
- "Write description and phasing"

**What it does:** Generates description first, then phasing. Individual status updates for each.

---

## Artifact Reading

### Read Description
Reads the description document aloud.

**Voice commands:**
- "Read the description"
- "Read description"

**What it does:** Loads `artifacts/description.md` and speaks entire content via TTS. Interruptible.

---

### Read Phasing
Reads the entire phasing document aloud.

**Voice commands:**
- "Read the phasing"
- "Read phasing"

**What it does:** Loads `artifacts/phasing.md` and speaks all phases via TTS. Interruptible.

---

### Read Specific Phase
Reads a single phase aloud.

**Voice commands:**
- "Read phase 3"
- "Read me phase two"
- "Read phase 1"

**What it does:** Extracts the specified phase from `phasing.md` and speaks only that phase's content (title, description, definition of done).

---

## Artifact Editing

### Edit Description
Regenerates description with new requirements.

**Voice commands:**
- "Edit the description to say X"
- "Update the description with Y"
- "Change the description to include Z"

**What it does:** Adds your edit instruction to conversation history as a requirement, then regenerates entire description incorporating all previous context plus the new requirement.

---

### Edit Phasing (Full)
Regenerates entire phasing with new requirements.

**Voice commands:**
- "Edit the phasing to include X"
- "Update the phasing with Y"

**What it does:** Adds edit instruction to conversation history, then regenerates all phases with the new requirement. Uses multi-pass generation.

---

### Edit Specific Phase
Edits a single phase using AI.

**Voice commands:**
- "Edit phase 2 to include authentication"
- "Change phase 1 to use TypeScript"
- "Update phase 5 with dark mode support"

**What it does:** Uses AI to modify only the specified phase. Preserves all other phases exactly. Creates backup before modification.

---

## Phase Manipulation

### Split Phase
Splits one phase into 2-4 sub-phases.

**Voice commands:**
- "Split phase 2 into frontend and backend work"
- "Break phase 3 into smaller tasks"
- "Split phase 1 into setup and configuration"

**What it does:**
- Uses AI to intelligently divide the phase based on your instructions
- Generates 2-4 sub-phases with separate titles, descriptions, and DoDs
- Renumbers all subsequent phases
- Creates backup before modification

**Example:**
```
Input: Phase 2: "Implement user system"
Split instruction: "database work and API work"

Output:
  Phase 2: "Create user database schema"
  Phase 3: "Implement user API endpoints"
  [Original phases 3+ become 4+]
```

---

### Merge Phases
Combines 2-5 consecutive phases into one.

**Voice commands:**
- "Merge phases 5 and 6"
- "Combine phases 2 and 3"
- "Merge phases 1 through 3"

**What it does:**
- Uses AI to synthesize multiple phases into one comprehensive phase
- Creates merged title, description, and definition of done
- Renumbers all subsequent phases
- Limit: Max 5 phases per merge
- Creates backup before modification

**Example:**
```
Input:
  Phase 3: "Create API client"
  Phase 4: "Connect UI to API"

Merge instruction: default (none provided)

Output:
  Phase 3: "Build and connect API client"
  [Original phases 5+ become 4+]
```

---

## Search

### Basic Search
Quick web search with concise summary.

**Voice commands:**
- "Search for X"
- "Look up Y"
- "Find information about Z"
- "Search the web for X"

**What it does:**
- Uses Perplexity API (or Brave fallback)
- Returns 2-3 sentence summary
- Optimized for TTS (no citations, clean prose)
- Adds result to conversation history for follow-up questions

---

### Deep Search
In-depth research with extended reasoning.

**Voice commands:**
- "Deep research X"
- "Do deep research on Y"
- "Research Z thoroughly"

**What it does:**
- Uses Perplexity reasoning model
- Returns 4-5 sentence comprehensive summary
- Includes reasoning and analysis
- Strips thinking blocks before TTS
- Adds result to conversation history

---

## Conversation

### General Conversation
Responds to questions and statements.

**Voice commands:**
- "How should I structure this?"
- "What's the best approach for X?"
- "I want to add feature Y"
- Any statement or question

**What it does:**
- Generates conversational response using full conversation history
- Simple statements → One word ("Noted", "Got it")
- Complex questions → Focused answer (one core idea)
- Never suggests searching
- Never asks clarifying questions unless incomprehensible

---

## Utility

### Repeat Last
Replays the last AI response.

**Voice commands:**
- "Repeat"
- "Repeat last"
- "Say that again"

**What it does:** Re-speaks the cached last response. Instant, no API call.

---

### Stop
Halts current operation.

**Voice commands:**
- "Stop"

**What it does:** Stops any ongoing action and returns to idle state.

---

### Copy Description
Copies description to clipboard.

**Voice commands:**
- "Copy description"
- "Copy the description"

**What it does:**
- Copies contents of `artifacts/description.md` to system clipboard
- Confirms: "Description copied to clipboard!"

---

### Copy Phasing
Copies phasing to clipboard.

**Voice commands:**
- "Copy phasing"
- "Copy the phasing"

**What it does:**
- Copies contents of `artifacts/phasing.md` to system clipboard
- Confirms: "Phasing copied to clipboard!"

---

### Copy Both
Copies both artifacts to clipboard.

**Voice commands:**
- "Copy both"
- "Copy both artifacts"

**What it does:**
- Combines description and phasing with separator (`---`)
- Copies combined content to clipboard
- Confirms: "Both artifacts copied to clipboard!"

---

## Action Summary

| Category | Actions | Count |
|----------|---------|-------|
| Writing | Write Description, Write Phasing, Write Both | 3 |
| Reading | Read Description, Read Phasing, Read Specific Phase | 3 |
| Editing | Edit Description, Edit Phasing, Edit Specific Phase | 3 |
| Phase Ops | Split Phase, Merge Phases | 2 |
| Search | Basic Search, Deep Search | 2 |
| Conversation | General Conversation | 1 |
| Utility | Repeat Last, Stop, Copy Description, Copy Phasing, Copy Both | 5 |

**Total: 19 distinct actions**

---

## How the Router Works

The Router is the intent classification layer. It takes user speech (transcribed text) and determines which action to execute.

### Core Process

1. **Input:** User transcript (from STT)
2. **Context:** Recent conversation + last search query
3. **LLM Call:** Groq API with system prompt
4. **Output:** Structured JSON with intent and action
5. **Validation:** JSON decoded into typed action
6. **Handoff:** Action sent to Orchestrator

### Router Configuration

**API:** Groq Chat Completions (`https://api.groq.com/openai/v1/chat/completions`)

**Model:** Configurable via `LLM_MODEL_ID` env var (default: `moonshotai/kimi-k2-instruct-0905`)

**Parameters:**
- `temperature: 0.1` - Low temperature for consistent routing
- `max_tokens: 400` - Enough for complex action parameters
- `response_format: json_object` - Forces valid JSON output

**Transcript handling:**
- Truncates to 1500 chars if longer (prevents token overflow)
- Appends "..." to indicate truncation

### Context Building

The router receives context to make smarter decisions:

**Recent Messages (last 10):**
```
Recent conversation (newest last):
user: I want to build a habit tracker
assistant: Noted. Tell me more.
user: Search for habit tracking UX patterns
assistant: Searching... [results]
```

**Last Search Query:**
```
Last search query: habit tracking UX patterns
```

**Current Input:**
```
Current user input: what about gamification?
```

Combined, this allows the router to understand follow-up questions like "what about gamification?" refers to the previous search context.

### System Prompt

The router uses a detailed system prompt with exact JSON format examples for every action:

```
Route user input to appropriate action. Return EXACT JSON format shown in examples.

ACTIONS AND EXACT JSON FORMATS:

SEARCH:
"search for X" → {"intent": "directive", "action": {"action": "search", "query": "X"}}

DEEP SEARCH:
"deep research X" → {"intent": "directive", "action": {"action": "deep_search", "query": "X"}}

WRITE:
"write the description" → {"intent": "directive", "action": {"action": "write_description"}}
"write both" → {"intent": "directive", "action": {"action": "write_both"}}

READ:
"read the description" → {"intent": "directive", "action": {"action": "read_description"}}
"read phase 1" → {"intent": "directive", "action": {"action": "read_specific_phase", "phaseNumber": 1}}

EDIT:
"edit the description to say X" → {"intent": "directive", "action": {"action": "edit_description", "content": "X"}}
"edit phase 2 to include X" → {"intent": "directive", "action": {"action": "edit_phasing", "phaseNumber": 2, "content": "include X"}}

SPLIT/MERGE PHASES:
"split phase 2 into frontend and backend work" → {"intent": "directive", "action": {"action": "split_phase", "phaseNumber": 2, "instructions": "frontend and backend work"}}
"merge phases 5 and 6" → {"intent": "directive", "action": {"action": "merge_phases", "startPhase": 5, "endPhase": 6}}

COPY:
"copy description" → {"intent": "directive", "action": {"action": "copy_description"}}

NAVIGATION:
"repeat" → {"intent": "directive", "action": {"action": "repeat_last"}}
"stop" → {"intent": "directive", "action": {"action": "stop"}}

CONVERSATION (default for questions/discussion):
"how does X work?" → {"intent": "conversation", "action": {"action": "conversation", "content": "how does X work?"}}
"I want to build X" → {"intent": "conversation", "action": {"action": "conversation", "content": "I want to build X"}}

CRITICAL: Use EXACT action names shown above (e.g., "edit_phasing" not "edit_phase")
```

This teaches the LLM exactly which JSON structure to return for each type of input.

### Intent Types

**`directive`** - Explicit command with deterministic action
- Examples: write, read, edit, search, copy, split, merge
- No ambiguity - clear intent to execute specific operation
- Router extracts parameters (phase numbers, queries, instructions)

**`conversation`** - Open-ended question or statement
- Examples: "How should I structure this?", "I want authentication"
- Requires conversational LLM response
- Full user input passed as `content` parameter

### JSON Response Format

**Top-level structure:**
```json
{
  "intent": "directive" | "conversation",
  "action": { ... },
  "reasoning": "optional explanation"
}
```

**Action structures by type:**

**Simple (no parameters):**
```json
{"action": "write_description"}
{"action": "read_phasing"}
{"action": "copy_both"}
{"action": "repeat_last"}
{"action": "stop"}
```

**With single parameter:**
```json
{"action": "read_specific_phase", "phaseNumber": 3}
{"action": "edit_description", "content": "add dark mode support"}
{"action": "search", "query": "React hooks patterns"}
{"action": "deep_search", "query": "transformer architecture"}
```

**With multiple parameters:**
```json
{"action": "edit_phasing", "phaseNumber": 2, "content": "include authentication"}
{"action": "split_phase", "phaseNumber": 3, "instructions": "frontend and backend work"}
{"action": "merge_phases", "startPhase": 4, "endPhase": 6, "instructions": "optional"}
```

**Conversation:**
```json
{"action": "conversation", "content": "how does authentication work?"}
```

### Parameter Extraction

The router intelligently extracts parameters from natural language:

**Phase numbers:**
- "read phase 3" → `phaseNumber: 3`
- "edit phase two" → `phaseNumber: 2`
- "split phase 5" → `phaseNumber: 5`

**Phase ranges:**
- "merge phases 2 and 3" → `startPhase: 2, endPhase: 3`
- "merge phases 1 through 5" → `startPhase: 1, endPhase: 5`
- "combine phases 4, 5, and 6" → `startPhase: 4, endPhase: 6`

**Search queries:**
- "search for React hooks" → `query: "React hooks"`
- "look up GraphQL best practices" → `query: "GraphQL best practices"`
- "find information about authentication" → `query: "authentication"`

**Edit instructions:**
- "edit phase 2 to include dark mode" → `phaseNumber: 2, content: "include dark mode"`
- "change the description to add TypeScript" → `content: "add TypeScript"`

**Split/merge instructions:**
- "split phase 3 into setup and implementation" → `phaseNumber: 3, instructions: "setup and implementation"`
- "break phase 2 into smaller pieces" → `phaseNumber: 2, instructions: "smaller pieces"`

### Parsing and Validation

1. **LLM returns JSON string** in response content
2. **Parse JSON** into dictionary
3. **Decode into `RouterResponse`** struct
4. **Decode nested `ProposedAction`** enum
5. **Validate action name** matches known actions
6. **Extract parameters** based on action type
7. **Return typed action** to orchestrator

**Error handling:**
- Unknown action name → throws decoding error → falls back to conversation
- Missing required parameter → throws error → falls back to conversation
- Invalid JSON → throws error → user sees "routing failed"

### Action Name Mapping

The router uses snake_case action names in JSON (for LLM clarity), which map to Swift enum cases:

| JSON Action | Swift Enum Case |
|-------------|-----------------|
| `write_description` | `.writeDescription` |
| `write_phasing` | `.writePhasing` |
| `write_both` | `.writeBoth` |
| `read_description` | `.readDescription` |
| `read_phasing` | `.readPhasing` |
| `read_specific_phase` | `.readSpecificPhase(Int)` |
| `edit_description` | `.editDescription(String)` |
| `edit_phasing` | `.editPhasing(Int?, String)` |
| `split_phase` | `.splitPhase(Int, String)` |
| `merge_phases` | `.mergePhases(Int, Int, String?)` |
| `search` | `.search(String)` |
| `deep_search` | `.deepSearch(String)` |
| `conversation` | `.conversation(String)` |
| `repeat_last` | `.repeatLast` |
| `stop` | `.stop` |
| `copy_description` | `.copyDescription` |
| `copy_phasing` | `.copyPhasing` |
| `copy_both` | `.copyBoth` |

Note: `edit_phase` is accepted as alias for `edit_phasing` (handled in decoder).

### Context Awareness Examples

**Follow-up search:**
```
History: user: "search for React state management"
         assistant: "Redux and Context API are most popular..."
Current: "what about MobX?"

Router decision: conversation (not new search, builds on previous)
```

**Implicit phase reference:**
```
History: user: "read phase 3"
         assistant: [reads phase 3]
Current: "edit it to include authentication"

Router decision: edit_phasing with phaseNumber: 3 (infers "it" = phase 3)
```

**Ambiguous input:**
```
Current: "I want dark mode"

Router decision: conversation (not directive, no explicit action verb)
```

**Multi-step intent:**
```
Current: "write both artifacts"

Router decision: write_both (recognizes "both" as special case)
```

### Retry and Resilience

**Network retry:** Uses `NetworkManager.performRequestWithRetry()` with exponential backoff

**Rate limiting:** Detects 429 status, waits and retries

**Token limits:** Truncates transcript to 1500 chars before sending

**Malformed JSON:** Falls back to conversation action on parse failure

**Unknown actions:** Logs warning, throws error, orchestrator treats as conversation

### Router Performance

**Latency:** ~200-500ms for routing decision
- Network roundtrip to Groq
- JSON parsing and validation
- Negligible overhead vs raw LLM call

**Accuracy:** High precision with examples-based prompt
- Few-shot learning via system prompt examples
- Low temperature (0.1) reduces randomness
- JSON mode forces valid structure

**Failure rate:** <1% with proper context
- Most failures from ambiguous input → conversation fallback
- Network errors handled by retry logic

---

## Execution Flow

1. **User speaks** → STT (Groq Whisper)
2. **Transcript** → Router with context (last 10 messages + search query)
3. **Router** → LLM call (Groq API, JSON mode, temp 0.1)
4. **LLM** → JSON response with intent and action
5. **Router** → Parse and validate JSON
6. **Proposed Action** → Orchestrator queue
7. **Orchestrator** → Sequential execution (single-threaded)
8. **Result** → TTS (spoken response)

All actions execute in a single-threaded queue. No parallel operations. IoGuard (`isExecuting`) prevents concurrent modifications.

### Full Flow Example

```
User: "split phase 2 into frontend and backend work"
  ↓
STT: "split phase 2 into frontend and backend work"
  ↓
Router Context:
  Recent messages: [last 10 turns]
  Last search: "React component architecture"
  ↓
Router Prompt:
  System: [routing examples]
  User: "Recent conversation: ... \n\nCurrent input: split phase 2..."
  ↓
Groq LLM:
  {
    "intent": "directive",
    "action": {
      "action": "split_phase",
      "phaseNumber": 2,
      "instructions": "frontend and backend work"
    }
  }
  ↓
Router Parse:
  ProposedAction.splitPhase(2, "frontend and backend work")
  ↓
Orchestrator:
  Enqueues action → Executes when idle → Splits phase 2
  ↓
TTS: "Splitting phase 2... Phase 2 split successfully."
```
