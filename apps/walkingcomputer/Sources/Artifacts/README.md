# Artifacts Module

This module manages all artifact-related operations with clear separation of concerns.

## Structure

**ArtifactStore** - Pure file I/O layer
- Read and write files atomically
- Manage backups automatically
- List and check file existence
- No business logic, just reliable storage

**PhaseEditor** - Phase manipulation logic
- Split phases into sub-phases
- Merge multiple phases into one
- Edit individual phases with AI assistance
- Uses ArtifactStore for all file operations

**PhaseParser** - Phase parsing and serialization
- Parse markdown into Phase objects
- Convert Phase objects back to markdown
- AI-powered split/merge operations
- Stateless utility functions

## Why This Separation?

This architecture enables future artifact types without modifying storage logic:

- **Software projects**: description.md, phasing.md (current)
- **Research**: summary.md, sources.md, key_insights.md (future)
- **Journaling**: entry-YYYY-MM-DD.md (future)
- **Game design**: design_doc.md, development_plan.md (future)

Each domain can have its own editor (ResearchEditor, DiaryEditor, etc.) while sharing the same ArtifactStore.

## Usage Pattern

```swift
// Initialize once
let store = ArtifactStore()
let phaseEditor = PhaseEditor(store: store, groqApiKey: apiKey)

// Read/write operations
store.write(filename: "description.md", content: content)
let content = store.read(filename: "phasing.md")

// Phase operations
await phaseEditor.splitPhase(2, instructions: "Split into frontend and backend")
await phaseEditor.mergePhases(4, 5, instructions: nil)
await phaseEditor.editPhase(3, instructions: "Add authentication")
```

## Design Principles

1. **Single Responsibility** - Each class has one clear purpose
2. **Composition** - Editors use ArtifactStore, don't inherit from it
3. **Testability** - Pure functions where possible, dependencies injected
4. **Extensibility** - New artifact types add new editors, not new stores
