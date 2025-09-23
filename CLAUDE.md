# Walkcoach Speccer - Single-Threaded Edition

## Project Name
walkcoach speccer, single-threaded edition.

## What We Are Building
We're building a voice-first speccer that talks with you while you walk and, on command, writes and reads two living artifacts for any project: a spoken project description and a spoken phasing plan. Everything happens in one loop, one action at a time. There are no background writes and no hidden threads. When you say "write the description," it says "writing now," writes exactly one file, and then asks if you want it read back. When you say "edit phase one to do x, y, z," it says "editing now," applies a tiny patch, and then offers to read the updated phase. Reads, writes, and edits are explicit actions that go through the same queue.

## How It Feels in Use
You hold a key, you talk, you let go. The speccer answers in one to three short sentences, like a sharp secretary. It proposes the next step when helpful, and it never touches files unless you ask. When you approve an action, it executes immediately, then tells you it's done, and offers to read the result. You can interrupt any read with a new command and it switches tracks without confusion. If you say "repeat last," it replays the last answer instantly from cache. If you say "read phase three," it reads the stored talk track for that phase.

## The Core Behavior
The heart is a single orchestrator that owns a turn context and an action queue. Legal actions are read, write, and edit. Read means "open a target artifact and speak its text." Write means "generate full text for a target artifact and commit it atomically." Edit means "apply a small patch to a target artifact and commit it atomically." Only the orchestrator may touch disk, and it does so during the "executing" state, never in parallel. The router never writes; it only proposes or parses directives.

## The Artifacts
There are exactly two user-facing artifacts per project:
1. `artifacts/description.md` - pitches the project in plain english and reads well out loud
2. `artifacts/phasing.md` - lists numbered phases, each with a one-paragraph "talk track" that is easy to read into your ear

Edits are incremental. We apply unified diffs for markdown and keep timestamped backups and `.reject` files on conflicts. We also keep a tiny index, `artifacts/phasing_index.json`, that maps each phase number to its talk track and, once synthesized, to a cached audio path for instant replay.

## Voice Navigation You Can Trust
Simple voice commands are handled locally before any model call: "yes," "no," "write description," "write phasing," "read description," "read phasing," "edit phasing," "repeat last," "next phase," "previous phase," and "stop." If a command matches this small grammar, we run it immediately through the orchestrator. If it doesn't, we ask the model to interpret it and return a structured proposal.

## The Stack and Constraints
- Rust, push-to-talk, and non-streaming
- Speech-to-text: Groq Whisper Turbo
- Thinking model: Kimi K2 on Groq
- Text-to-speech: defaults to Groq TTS, with ElevenLabs as optional
- Only one secret required: `GROQ_API_KEY` in `.env`
- Everything else is local
- Logs are JSONL, one line per turn, with timings for record, STT, LLM, TTS, and speak
- Artifacts and caches live under the repo

## Why Single-Threaded Matters Here
You're walking. You need predictability. A single event loop means no surprise edits, no racing reads, and clean hand-offs. The speccer narrates its own state in short lines—"writing description," "done," "reading phasing"—so you always know what is happening without looking. Interruptions are safe and clear: reading stops, the new action queues, and the loop continues.

## What "Good" Looks Like
From "yes, write it" to "done," it feels snappy and linear. The files on disk always reflect exactly what the agent said it did. Repeats are instant. Edits are tiny and reversible. When you export the project, you get a single paste-ready brief composed of the current description, the current phasing, and a short slice of recent turns.

## What's in Scope Now
- The single-threaded orchestrator
- The router that proposes actions instead of executing them
- Read and write of `description.md` and `phasing.md`
- Safe edits via unified diff
- Local voice commands
- Atomic file commits with backups
- Cached audio for talk tracks
- Clean logs

Research mode and long "thinking mode" can be added later without changing the loop.

## Example Session
**You:** "hey, i want to build a snake game with poppy colors, smooth animations for milestones, basic background melody, and it should run in javascript."  
**Speccer:** "Got it. Do you want me to write the description, or add more details?"  
**You:** "Write the description."  
**Speccer:** "Writing now… done. Do you want me to read it?"  
**You:** "Yes."  
*Speccer reads it. You interrupt.*  
**You:** "Move to the phasing."  
**Speccer:** "Write the phasing?"  
**You:** "Yes."  
**Speccer:** "Writing now… done. Read it?"  
**You:** "Yes."  
*Speccer reads it. You interrupt again.*  
**You:** "For phase one, make the controls responsive on mobile."  
**Speccer:** "Editing phase one… updated. Want me to read the phasing again?"

## Key Principle
**A single-threaded, voice-first speccer that writes and reads two artifacts on command, and never does anything behind your back.**

## Implementation Phases

### Phase 7: Chunked Reading ✅
Read artifacts in manageable chunks with pauses between them.
- Description: Read in paragraphs with brief pauses ✅
- Phasing: Read phase by phase with "Next phase?" prompts ✅
- Allow interruption between chunks ✅
- Cache chunks for quick navigation ✅

**Test Procedure:**
1. Say "read the phasing slowly" - Should read phase 1, pause, then ask "Continue (chunk 2 of N)?"
2. Say "yes" - Should read phase 2, pause, ask again
3. Say "stop" during a phase - Should stop immediately
4. Say "read phase 3" - Should jump directly to phase 3
5. Say "read description slowly" - Should read first paragraph, then ask to continue

### Phase 8: Context-Aware Assistant (Next)
Add conversation memory to fix confirmation issues.

### Phase 9: Advanced Edit Operations (Future)
Targeted edits like "change phase 2 to..." and append/prepend operations.

### Phase 10: Polish & Production (Future)
Configuration, voice selection, speed controls.

## Current Status
✅ Phase 0-6: Complete
✅ Artifact editor disabled (single-threaded execution restored)
✅ Phase 7: Complete (chunked reading implemented)