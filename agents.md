# Development Agents & Workflow

## Branch Structure Philosophy

### Each Branch is a Complete Application
**IMPORTANT**: In the CodeWalk project, each branch represents a complete, runnable application at a specific phase of development. This means:
- **No subdirectories for projects** - The Rust project files live at the root of each branch
- **Branch-specific READMEs** - Each branch has its own README explaining that phase
- **Self-contained functionality** - Each branch can be cloned and run independently

### Why This Approach?
1. **Clarity**: Clone any branch and immediately have a working application
2. **Simplicity**: No navigation through subdirectories to find the actual code
3. **History**: Each phase preserved as a complete snapshot
4. **Independence**: Phases can diverge without affecting others

## Git Worktree Strategy

Each phase of the CodeWalk project lives in its own git worktree:

### Why Worktrees?

Traditional branching requires constant stashing and switching. Worktrees give us:
- **Parallel Development**: Work on multiple phases simultaneously
- **Clean Separation**: Each phase has its own directory
- **Shared History**: All worktrees share the same git repository
- **No Context Switching**: Keep terminals, editors, and builds running in each phase

### Current Structure

```
Documents/
├── codewalk/           # Main branch - Production release
│   ├── src/            # Rust source code (at root!)
│   ├── Cargo.toml      # Rust project file (at root!)
│   ├── README.md       # Main branch documentation
│   ├── agents.md       # This file
│   └── vision-roadmap.md
│
└── codewalk-app/       # phase-2-tauri-app branch worktree
    ├── src/            # Same Rust code structure
    ├── Cargo.toml      # Enhanced for Tauri
    ├── README.md       # Phase 2 specific docs
    └── [Tauri additions]
```

### Branch Purposes

- **main**: Current stable release, always deployable
- **phase-1-terminal-stt**: Historical - Terminal STT implementation (complete)
- **phase-2-tauri-app**: Active development - Tauri GUI version
- **phase-3-***: Future phases as needed

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
2. **Structure**: Ensure project files are at root (no subdirectories!)
3. **Document**: Create phase-specific README
4. **Develop**: Work in isolated directory
5. **Commit**: Changes go to phase-specific branch
6. **Complete**: Merge to main when ready
7. **Archive**: Keep branch for historical reference

## Agent Responsibilities

### Phase Transitions
When moving between phases:
- Ensure previous phase is committed
- Create new worktree for next phase
- Move project files to root if needed
- Update README for phase context
- Update vision-roadmap.md with progress
- Maintain clean separation between phases

### File Organization Rules
1. **NEVER** create project subdirectories (no `stt-clipboard/`, `tauri-app/`, etc.)
2. **ALWAYS** place Cargo.toml and src/ at the repository root
3. **ALWAYS** update README.md to reflect the current phase
4. **PRESERVE** shared documentation (agents.md, vision-roadmap.md)

### Context Management
- Each worktree maintains its own state
- Configuration can be shared via main branch
- Dependencies tracked per-phase in Cargo.toml
- Phase-specific features documented in README

### Testing Strategy
- Phase 1: Terminal application, local testing
- Phase 2: Tauri desktop app, cross-platform testing
- Phase 3+: Enhanced features, comprehensive testing
- Each phase must be independently functional

## Branch Merging Strategy

When a phase is complete:
1. Ensure all tests pass
2. Update main README if needed
3. Merge phase branch to main
4. Tag the release
5. Keep phase branch for reference
6. Start next phase from updated main

## Important Notes

- **Production Ready**: Main branch should always be production-ready
- **Phase Independence**: Each phase branch should work standalone
- **Documentation**: Every branch needs clear setup and usage instructions
- **No Nesting**: Project files always at root, never in subdirectories