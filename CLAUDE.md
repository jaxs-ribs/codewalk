# Walking Computer Speccer - Single-Threaded Edition

## Project Name
Walking computer speccer, single-threaded edition.

## What We Are Building
We're building a voice-first speccer that talks with you while you walk and, on command, writes and reads two living artifacts for any project: a spoken project description and a spoken phasing plan. Everything happens in one loop, one action at a time. There are no background writes and no hidden threads. When you say "write the description," it says "writing now," writes exactly one file, and then asks if you want it read back. When you say "edit phase one to do x, y, z," it says "editing now," applies a tiny patch, and then offers to read the updated phase. Reads, writes, and edits are explicit actions that go through the same queue.

## How It Feels in Use
You hold a key, you talk, you let go. The speccer answers in one to three short sentences, like a sharp secretary. It proposes the next step when helpful, and it never touches files unless you ask. When you approve an action, it executes immediately, then tells you it's done, and offers to read the result. You can interrupt any read with a new command and it switches tracks without confusion. If you say "repeat last," it replays the last answer instantly from cache. If you say "read phase three," it reads the stored talk track for that phase.

## The Core Behavior
The heart is a single orchestrator that owns a turn context and an action queue. Legal actions are read, write, and edit. Read means "open a target artifact and speak its text." Write means "generate full text for a target artifact and commit it atomically." Edit means "apply a small patch to a target artifact and commit it atomically." Only the orchestrator may touch disk, and it does so during the "executing" state, never in parallel. The router never writes; it only proposes or parses directives.

## The Artifacts
There are exactly two user-facing artifacts per project:
1. `artifacts/description.md` - pitches the project in plain english and reads well out loud
2. `artifacts/phasing.md` - lists numbered phases, each with a one-paragraph "talk track" that is easy to read into your ear. Phasing contains a definition of done which has a deliverable that is testable by the user.


## Voice Navigation You Can Trust
Simple voice commands are handled locally before any model call: "yes," "no," "write description," "write phasing," "read description," "read phasing," "edit phasing," "repeat last," "next phase," "previous phase," and "stop." If a command matches this small grammar, we run it immediately through the orchestrator. If it doesn't, we ask the model to interpret it and return a structured proposal.

## Why Single-Threaded Matters Here
You're walking. You need predictability. A single event loop means no surprise edits, no racing reads, and clean hand-offs. The speccer narrates its own state in short lines—"writing description," "done," "reading phasing"—so you always know what is happening without looking. Interruptions are safe and clear: reading stops, the new action queues, and the loop continues.

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

## Build Instructions
To build and run the Walking Computer Speccer:

```bash
# Navigate to the project directory
cd /Users/fresh/Documents/codewalk/apps/walkingcomputer

# Generate the Xcode project
xcodegen generate

# Build for iOS Simulator
xcodebuild -project WalkingComputer.xcodeproj -scheme WalkingComputer -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build

# Run tests
xcodebuild test -project WalkingComputer.xcodeproj -scheme WalkingComputer -destination "platform=iOS Simulator,name=iPhone 16,OS=latest"

# Deploy to phone (requires device to be connected)
./deploy-phone.sh
```

## Important Instruction Reminders
- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User
- NEVER write anything with git commands unless explicitly asked by the user. No git add, no git commit, no git status unless the user specifically requests it
