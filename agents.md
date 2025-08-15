# Development Agents & Workflow

## Git Worktree Strategy

Each phase of the Walk + Productivity project lives in its own git worktree:

### Why Worktrees?

Traditional branching requires constant stashing and switching. Worktrees give us:
- **Parallel Development**: Work on multiple phases simultaneously
- **Clean Separation**: Each phase has its own directory
- **Shared History**: All worktrees share the same git repository
- **No Context Switching**: Keep terminals, editors, and builds running in each phase

### Current Structure

```
Documents/
├── codewalk/           # Main branch - Foundation & vision
│   ├── stt-clipboard/  # Phase 1: STT clipboard (COMPLETE)
│   └── vision-roadmap.md
│
└── codewalk-app/       # phase-2-tauri-app branch
    └── [Tauri GUI port will live here]
```

### Workflow Commands

```bash
# List all worktrees
git worktree list

# Create new worktree for next phase
git branch phase-3-voice-assistant
git worktree add ../codewalk-voice phase-3-voice-assistant

# Remove worktree when phase is complete and merged
git worktree remove ../codewalk-voice
```

### Development Flow

1. **Start Phase**: Create branch and worktree
2. **Develop**: Work in isolated directory
3. **Commit**: Changes go to phase-specific branch
4. **Complete**: Merge to main when ready
5. **Archive**: Remove worktree (optional)

## Agent Responsibilities

### Phase Transitions
When moving between phases:
- Ensure previous phase is committed
- Create new worktree for next phase
- Update vision-roadmap.md with progress
- Maintain clean separation between phases

### Context Management
- Each worktree maintains its own state
- Configuration can be shared via main branch
- Dependencies tracked per-phase in respective directories

### Testing Strategy
- Phase 1: Local testing only
- Phase 2+: Must work on phone (TestFlight)
- Each phase must be independently functional