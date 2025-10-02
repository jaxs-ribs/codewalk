# Walking Computer: Voice-First Productivity System

## What It Is

Walking Computer is a voice-first productivity system designed for knowledge work while moving. You hold a button, talk, and the AI assists you in creating, refining, and executing structured work—all optimized for listening rather than reading. It's built around three pillars: Specification, Execution, and Verification.

The core idea: productivity liberated from the desk. Think while walking, research while commuting, spec while exercising, execute remotely, and verify visually. The system acts like having a highly intelligent team at your workstation that you direct via voice while you're anywhere else.

## The Three Pillars

### Pillar 1: Specification (Current)

**What it does:** Helps you define and plan projects through voice conversation.

You walk and talk. The AI listens, asks clarifying questions when needed, researches topics you're uncertain about, and distills everything into clear artifacts. For software projects, this means a project description and a phased implementation plan. For research, this means summaries and key insights. For journaling, this means structured entries from scattered thoughts.

**The conversation is optimized for listening.** The AI responds in 1-3 short sentences, using natural language like you're talking to a sharp assistant. Simple statements get simple acknowledgments: "Noted." "Got it." Complex questions get focused answers—one core idea at a time, never overwhelming you with information while you're moving.

**Research is built-in.** You can say "search for React hooks patterns" or "do deep research on transformer architecture" and the AI searches, reads sources, and speaks a synthesized summary. No link dumping. No reading required. Just answers you can listen to while walking.

**Artifacts are living documents.** The system creates markdown files that capture your specifications. For software projects, you get:
- **Description**: A conversational project pitch (1200-1800 characters) that reads well out loud
- **Phasing**: Numbered implementation phases, each with a clear definition of done

These aren't static documents. You can edit them via voice: "Edit phase 3 to include authentication." The AI updates the artifact and reads it back.

**Phases can be manipulated.** You can split a phase into smaller pieces: "Split phase 2 into frontend work and backend work." The AI intelligently divides it, renumbers everything, and maintains consistency. You can merge phases: "Combine phases 4 and 5." The AI synthesizes them into a cohesive unit.

**Example conversation:**
```
You: "I want to build a habit tracker with streak visualization."
AI: "Noted. Tell me more."
You: "Search for best habit tracking UX patterns."
AI: "Searching... The most effective pattern is chain-don't-break visualization
     with daily streaks. Duolingo popularized this approach."
You: "Good. Add dark mode and local storage."
AI: "Got it."
You: "Write the phasing."
AI: "Writing phasing... Reviewing... Done. Created 7 phases."
You: "Read phase 1."
AI: "Phase 1: Set up project structure and install dependencies. Create
     React app with TypeScript and Tailwind CSS. Definition of done:
     run npm start, app loads at localhost 3000 showing blank page."
```

**The system is opinionated.** It enforces good practices through its design:
- Every phase must have a testable "definition of done"
- Phases are atomic—one focused capability per phase, not mega-tasks
- Definitions of done test only what that specific phase built, not the entire system
- Responses are TTS-optimized—short sentences, contractions, flowing prose

This isn't a neutral tool. It has a point of view about effective specification and guides you toward it.

### Pillar 2: Execution (Future)

**What it will do:** Execute your specifications on your remote workstation while you walk.

After you finish speccing a project, you say "Start executing the phasing." The system connects to your home or office computer and begins implementing each phase using AI coding agents like Claude Code, OpenAI Codex, or Cursor.

**Each phase becomes an executable prompt.** The phasing document you created isn't just a plan—it's the actual prompt fed to the executor agent:
```
Phase 3: Create database schema for users
→ Agent reads phase description and definition of done
→ Agent writes migration files, creates schema
→ Agent runs tests specified in definition of done
→ Agent reports completion
```

**You monitor progress via voice.** While continuing your walk, you can check in:
```
You: "What's the status?"
AI: "Phase 3 is running. Currently implementing user schema migrations.
     Created the users table with email and password hash. Writing tests now."

You: "Any issues?"
AI: "Yes, one bug. The password column was missing a length constraint.
     I've fixed it and re-running the migration."
```

The executor agent's output (logs, error messages, git diffs) is summarized in real-time by an LLM and spoken to you. You don't read logs—you listen to summaries.

**You control execution remotely:**
- "Pause after phase 5"
- "Skip to phase 7"
- "Restart the current phase"
- "Show me the diff" (spoken summary)
- "Commit the changes"

**Smart features:**
- If a phase fails, the executor retries with error context
- If tests fail, the executor debugs and fixes
- If dependencies are missing, the executor installs them
- Execution state persists—you can pause, resume across walks

**The workflow:** Spec while walking to the coffee shop (20 min), execute while you're there having coffee (40 min), arrive home to nearly-complete implementation.

### Pillar 3: Verification (Future)

**What it will do:** Let you test implementations visually through voice-driven UI automation.

After execution completes, you say "Show me the app." Your phone displays a live screen stream from your workstation running the application. You test it entirely through voice commands.

**Computer-use agents translate voice to actions.** You speak natural commands and a vision-powered agent executes them:
```
You: "Navigate to the login page."
AI: "Clicking login in the navigation menu."
[Screen shows login form]

You: "Enter username test@example.com"
AI: "Typing in the username field."

You: "Enter password 12345"
AI: "Typing in the password field."

You: "Click the login button."
AI: "Clicking login."
[Screen shows error: "Invalid credentials"]

You: "Unexpected. Check the logs."
AI: "Opening dev console. I see a 401 error from the API.
     The endpoint is /api/auth/login but the backend is listening
     on /api/v1/login. Path mismatch."
```

**The agent can read screens, click elements, type text, and inspect state.** You don't touch the screen—you direct it with voice. The agent understands context: "click the blue button" or "scroll down" or "what's the error message?"

**This closes the loop.** When you find issues during verification, you go back to specification: "Edit phase 4 to use /api/v1/login endpoint." The system updates the phase, re-executes, and you verify again. Spec → Execute → Verify → Refine → Repeat.

**Advanced capabilities:**
- "Run the smoke test scenario" - predefined test flows
- "Compare this screen to the design mockup" - visual regression
- "Test on iPhone 12" - multi-device testing
- "Does this match the requirements?" - validation

## The Complete Development Loop

Imagine shipping production-ready code with 15 minutes of active work, while the rest happens during your morning walk:

**9:00 AM - Walking to work:**
```
You: "New project. I want to build a todo app with drag-and-drop."
AI: "Noted. What else?"
You: "Search for React drag and drop libraries."
AI: "Searching... React DnD is the most popular. Uses HTML5 drag-and-drop
     with React hooks. Supports touch devices."
You: "Good. Add local storage persistence."
AI: "Got it."
You: "Write the phasing."
AI: "Writing phasing... Reviewing... Done. 7 phases ready."
You: "Start executing."
AI: "Connecting to workstation. Beginning phase 1."
```

**9:30 AM - Arrive at office, grab coffee:**
```
You: "Status?"
AI: "Phase 4 complete. Drag-and-drop working. Starting phase 5:
     local storage persistence."
```

**10:00 AM - At your desk:**
```
You: "Show me the app."
AI: "Screen sharing now."
You: "Create a todo 'Buy coffee'"
AI: "Typing in the input. Todo created."
You: "Drag it to the complete list."
AI: "Dragging 'Buy coffee' to complete. Todo moved successfully."
You: "Refresh the page."
AI: "Refreshing. Todo still in complete list. Local storage working."
You: "Perfect. Commit and push."
AI: "Committed all phases. Pushed to main."
```

**10:15 AM - Shipping production code.** You spent 15 minutes actively directing. The rest happened in parallel with your morning routine.

## Beyond Software Development

The core capability is **voice-driven structured thinking**. Software development is just one application. The same system works for any knowledge work.

### Deep Research

**Use case:** Understanding complex papers or technical topics while walking.

You ask questions, the AI searches and explains concepts simply, and you iteratively build understanding. At the end, you say "Write the description" and get a comprehensive, TTS-optimized summary document.

```
You: "I want to understand transformer architecture."
AI: "Noted."
You: "Deep research on transformer architecture."
AI: "Researching... Transformers use self-attention mechanisms instead
     of recurrence. The 'Attention is All You Need' paper introduced
     them in 2017 for machine translation."
You: "What's self-attention?"
AI: "Self-attention lets each word look at every other word to understand
     context. It computes relevance scores between all word pairs."
You: "How is it implemented?"
AI: "It uses query, key, and value matrices. Each word is projected into
     these three spaces, then attention scores are computed as scaled
     dot products of queries and keys."
You: "Write the description."
AI: "Writing... Done."
You: "Read it back."
AI: [Reads comprehensive explanation]
```

**Output:** Distilled research summary in `description.md`.

### Voice-Only Diary

**Use case:** Journaling thoughts and daily events without typing.

You speak freely about your day, feelings, breakthroughs, and todos. The AI captures everything and distills it into a structured entry. You can search old entries: "Search my diary for mentions of Sarah."

```
You: "New diary entry for today."
AI: "Listening. What happened?"
You: "Had a breakthrough on the authentication bug. Token expiry wasn't
     accounting for timezone differences. Also, coffee meeting with Sarah
     went well, she's on board with the feature roadmap."
AI: "Noted. Anything else?"
You: "Feeling good about progress. Need to follow up on database migration
     tomorrow."
AI: "Got it."
You: "Write the description."
AI: "Writing... Done."
You: "Read it back."
AI: "October 2nd. Solved authentication bug—token expiry had timezone issues.
     Coffee with Sarah, she approved the feature roadmap. Good progress today.
     Tomorrow: follow up on database migration."
```

**Output:** Structured diary entry in `diary/2024-10-02.md`.

### Note Distillation

**Use case:** Capture scattered thoughts and organize them into coherent notes.

You brain-dump ideas during a walk. The AI listens without interrupting. When you're done, it structures your thoughts into themes and presents them back clearly.

```
You: "I want to capture some product ideas."
AI: "Go ahead."
You: "The main thing is simplicity. Users want the core workflow faster, not
     more features. Like the three-click rule—if the main action takes more
     than three clicks, we've failed."
AI: "Noted."
You: "Also, look at what Notion does with templates. Not to copy, but to
     understand why they work. It's about reducing decision fatigue."
AI: "Got it."
You: "And our search is terrible. It needs to be instant and understand
     context, not just keyword matching."
AI: "Noted."
You: "Write the description."
AI: "Writing... Done. I've structured it into three principles: simplicity,
     templates, and search."
You: "Read it."
AI: [Reads organized product vision]
```

**Output:** Structured notes in `description.md`.

### Calorie and Habit Tracking

**Use case:** Log meals, workouts, or habits throughout the day.

You report as you go: "Breakfast: oatmeal with berries, 300 calories." The AI logs it. You can check totals: "What's my calorie count?" The AI responds: "830 so far." At the end of the day, generate a summary.

### Game Design

**Use case:** Spec out games while walking, identical to software projects.

```
You: "I want to design a puzzle game about time manipulation."
AI: "Tell me more."
You: "The core mechanic is rewinding time. You make a mistake, rewind,
     and try again. But rewinding costs energy."
AI: "Noted."
You: "Search for time manipulation game mechanics."
AI: "Searching... Braid and Prince of Persia pioneered time rewind. Braid
     made it strategic by tying it to puzzle solutions, not just error correction."
You: "Good. I want puzzles where you need to rewind to solve them."
AI: "Got it."
You: "Write the phasing."
AI: "Writing... Done. Created 7 phases from prototype to full game."
You: "Read phase 1."
AI: "Phase 1: Build time rewind prototype. Create a player that can move and
     jump. Add a rewind button that reverses the last 5 seconds of movement.
     Definition of done: press spacebar, player rewinds to position from 5
     seconds ago, console logs the timeline."
```

**Output:** Game design doc (`description.md`) and development roadmap (`phasing.md`).

### Document Drafting

**Use case:** Draft emails, reports, or proposals via voice.

You provide key points and desired tone. The AI generates a draft, reads it to you, and you refine it: "Too formal. Make it conversational." When satisfied: "Copy to clipboard."

## The Opinionated Core

Walking Computer is **deliberately opinionated**. It enforces effective practices through its design, not as suggestions.

### TTS-First Communication

Every response is optimized for listening while moving:
- Short sentences (under 20 words)
- Natural contractions ("it's", "we'll", "don't")
- Flowing prose, no bullets or lists
- One idea per response
- No markdown, citations, or visual formatting

**Why:** Reading while walking is dangerous and breaks flow. The AI is your companion, speaking naturally.

### Definition of Done is Sacred

In software phasing (and equivalents for other domains):
- Every phase must have a testable "definition of done"
- The DoD tests only what that specific phase builds
- The DoD uses concrete commands and expected outputs
- No vague "feature works end-to-end" statements

Example good DoD: "Run npm start, app loads at localhost:3000, console shows no errors."

Example bad DoD: "User can register and log in successfully." (Too broad, tests multiple unbuilt components)

**Why:** Vague requirements lead to vague implementations. Testable DoDs enable autonomous execution by AI agents in Pillar 2.

### Atomic Phases

Each phase represents one focused capability:
- 5-8 phases total, not 3 mega-phases
- Each phase completable in one session
- No "setup X, then build Y, then add Z" in a single phase

**Why:** Small phases are executable by AI agents. Large phases fail during autonomous execution.

### Test-Driven Development Bias

Phases are often structured: setup → implement → test. Early phases test infrastructure pieces. Late phases test integration. DoDs verify specific mechanisms, not user stories.

**Why:** TDD catches bugs early. Autonomous agents need verification at each step.

### Spec Before Code

Complete specification before any execution. Research integrated into spec process. When issues arise during execution or verification, changes go back to the spec first.

**Why:** Prevents thrashing. AI agents execute exactly what you specify—garbage in, garbage out.

### Conversational Brevity

The AI responds concisely:
- Simple statements → One word ("Noted", "Got it", "Sure")
- Complex questions → One core idea, never multiple points
- Never enumerates or lists options
- Focuses on the single most important thing

**Why:** Cognitive overload while walking. Focus beats comprehensiveness.

These aren't preferences—they're embedded in the system prompts. The AI cannot respond differently.

## Universal Patterns

The system operates on patterns that work across all domains:

### Pattern 1: Capture → Distill → Review

1. Voice dump all thoughts (AI listens without interrupting)
2. AI distills into structure
3. Review via TTS (AI reads it back)
4. Refine as needed

**Works for:** Meeting notes, brainstorming, learning, journaling, planning.

### Pattern 2: Research → Synthesize → Document

1. Ask questions (AI searches and explains)
2. Iteratively build understanding
3. Generate comprehensive document
4. Review and refine

**Works for:** Academic research, market analysis, competitive research, technical deep-dives.

### Pattern 3: Specify → Execute → Verify

1. Spec what you want (via conversation)
2. Autonomous agent executes (Pillar 2)
3. Voice-driven verification (Pillar 3)
4. Refine and repeat

**Works for:** Software development, content creation, data analysis, design work.

## Domain Flexibility

The same architecture adapts to different domains through custom artifact templates:

**Software Development:**
- Artifacts: `description.md`, `phasing.md`
- Execution: Claude Code agents implement phases
- Verification: Computer-use agents test UI

**Research:**
- Artifacts: `summary.md`, `sources.md`, `key_insights.md`
- Execution: Deep research agents gather more data
- Verification: Citation checking

**Journaling:**
- Artifacts: `entry.md` (date-stamped)
- Execution: None (pure capture)
- Verification: None

**Game Design:**
- Artifacts: `design_doc.md`, `development_plan.md`
- Execution: Game engine agents build prototypes
- Verification: Playtest agents

The core remains identical: voice in, structured thinking, voice out.

## Why It Matters

**Traditional productivity:**
- Chained to a desk
- Context-switching between thinking and typing
- Reading-first interfaces
- Manual execution
- Manual testing

**Walking Computer:**
- Think while moving
- Voice-driven, hands-free
- Listening-first interface
- Autonomous execution (Pillar 2)
- Voice-driven testing (Pillar 3)

**The shift:** You become the director, not the implementer. The AI agents are your team:
- Specification AI: Your technical writer
- Execution AI: Your senior engineer
- Verification AI: Your QA tester

You walk, think, and direct. They build.

## The Vision Realized

Picture a Monday morning:

**9:00 AM:** Walking to work. "New project. Habit tracker with streak visualization."

**9:05 AM:** Still walking. "Search for habit tracking UX patterns." AI searches and explains. "Good, include that. Add dark mode."

**9:15 AM:** "Write the phasing." AI generates 8 phases. "Start executing." AI connects to your workstation and begins.

**9:30 AM:** Arrive at office. "Status?" AI: "Phase 4 complete. Streak visualization rendering. Phase 5 in progress."

**10:00 AM:** At desk. "Show me the app." Screen sharing starts. "Create a habit 'Meditate'." AI executes. "Mark it complete." Streak shows 1 day.

**10:15 AM:** "Perfect. Deploy to TestFlight." AI builds and uploads.

**Result:** Production-ready app shipped. You spent 15 minutes actively working. The rest happened while you walked.

This is productivity liberated from the desk. This is the Walking Computer.

## Current Status and Future

**Pillar 1: Specification** is complete and functional:
- Voice input/output via iOS app
- Artifact generation (description, phasing)
- Search integration (Perplexity, Brave)
- Phase manipulation (split, merge, edit)
- Conversation with context awareness
- TTS-optimized responses
- Clipboard integration

**Pillar 2: Execution** is planned:
- Workstation daemon for remote execution
- Claude Code and other executor agent integration
- Phase-as-prompt pipeline
- Real-time status summarization
- Voice control (pause, resume, skip, commit)

**Pillar 3: Verification** is planned:
- Screen streaming from workstation
- Computer-use agent integration
- Vision model for UI understanding
- Voice-driven testing commands
- Multi-device support

**Beyond:** Domain plugins, collaborative sessions, CI/CD integration, multi-project support.

The foundation is built. The future is expanding.
