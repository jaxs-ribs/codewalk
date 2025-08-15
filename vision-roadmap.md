# Walk + Productivity

## Vision

**Mission Statement**: "Maximize the time in a work day spent walking"

The core frustration with modern software: Most of it is gimmicks and solutionism. Grown adults hunched over computers at adult daycare. But walking while being productive? That's a legitimate non-gimmicky value add to life. If people can be outside doing meaningful work, that improves their lives.

**Key Principles**:
- High bandwidth + low latency are foundational for any good interface
- Context management must be local - no giving data to big corps
- Shift from quick answers to better answers
- Focus on a vertical slice of users (close friends) rather than the masses
- "Any sufficiently detailed spec becomes an implementation"

**Success Metric**: Can someone solve CTFs/hack the box while walking?

## Core Pipeline

Phone with STT → Agent → (TTS + Screen Results)

**Tools at disposal**:
- Phone with STT-Agent-(TTS + screen results) pipeline
- Daylight computer (for code/visual display while walking)
- AR Glasses (future target once occlusion issues solved)

## Roadmap: Useful Stepping Stones

Any stepping stone here has to be useful in some deliverable product.

### Phase 1: Foundation ✓

DONE
1. Simple on-computer stt detector (copy recorded speech to clipboard)
    1. Swappable groq key, swap in with tinyboxes later
    2. Essentially tiny aqua voice 
    3. Should take less than 2 hrs

---

2. Get Git worktrees to work to properly jump between projects
3. Port to a simple tauri GUI, so stt-clipboard-turbo works on computer
4. Get app to work on testflight (tauri gui)

### Phase 2: Voice Assistant

-- Every step from here must work on the phone --

5. Simple on-computer stt-llm interface 
    1. Just hook up the llm answers from groq 
    2. Should we have a /voice/ and /llm/ folder, or should it be /api/?
    3. Use tauri for cross platform and later phone use

6. Simple on-computer stt-llm-tts interface 
    1. Hook up the elevenlabs turbo api (or another model, find out)
    2. Same question with folders, should we just have separate folders that use /api/ utils?

### Phase 3: Context Engineering

7. Context engineering (Mandatory: context is local!)
    1. Simple chat history 
    2. Actually check out honcho, see if shoehorning works locally

8. Context engineering
    1. Good system prompt
    2. Trying to nudge it to do things like 'Useful stepping stones'
    3. Research mode (and then todo for a research MCP server)

### Phase 4: Research Capabilities

9. Research MCP server (or something else)
    1. Required Actions
        1. Discard research topic
        2. Summarize and create document for a topic
        3. Knowledge Tree Generation
    2. ...

### Phase 5: Beyond the Event Horizon

10. This is where event horizon lies. Guesses from here will be too imprecise, but it will be about either understanding a codebase or speccing out ideas. It will also have to coevolve that with the existing research mvp. Need connectors to other actions to unify the domains. Seriously focus on unification here.

## Use Cases

**Primary Actions**:
1. Do deep research on a topic by letting the agent automatically fill its context with papers (Solve)
2. Spec out ideas like games or projects (Coagula)
3. Understand a codebase (probably requires daylight computer or screen)

**Terminal-First Voice Commands**:
- "Open the context.rs file and display the blob() function"
- Converts to commands like `vi src/context.rs` or cat with line numbers
- Terminal is more aesthetic than VS Code forks which feel "unlean and cucked"

**Research Mode Ideas**:
- Paper companion with phases: discuss topic → find relevant papers → summarize → discuss
- Socratic thinking partner that actually asks good questions
- Interactive notebook LM with groq/kimi/whisper-turbo

## Future Considerations

**SpeedReader MindMap Groq**: When asking LLM questions, get `###` headers only, flash display them like speedreaders. Voice navigation to expand sections - essentially mindmap navigation autocreated through groq-kimi-k2.

**Later: "Autogenerate a 829 page book from interactive conversation and refinement"** (Needs to solve the API consolidator problem)

## Technical Notes

- NotebookLM is working on interactive mode
- Model/voice latency is diminishing
- Latency of 10s is acceptable while walking - it's about context, not speed
- A good custom prompt can do more than anything else
- Local models aren't there yet for productization without API consolidation