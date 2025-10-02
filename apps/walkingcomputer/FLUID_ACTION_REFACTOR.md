# Fluid Action Refactor Design Document

## Executive Summary

We are refactoring the Walking Computer Speccer from 18 discrete, keyword-based actions to 4 fluid, intention-based primitives. This change reduces the learning curve for new users while preserving all existing functionality. Instead of memorizing commands like "split phase 3" or "merge phases 5-6", users will speak naturally and the system will infer their intent.

## Motivation

The current system requires users to learn a specific vocabulary:
- "write description" vs "write phasing" vs "write both"
- "edit phase 2" vs "split phase 2" vs "merge phases 2-3"
- "read phasing" vs "read phase 5"

This creates friction for new users who must memorize keywords before being productive. Modern LLMs are capable of understanding natural language intent without rigid command structures. By removing the discretized routing layer, we create a more fluid experience while maintaining the same underlying capabilities.

## Core Changes

### Current State: 18 Discrete Actions
```
writeDescription, writePhasing, writeBoth
readDescription, readPhasing, readSpecificPhase(n)
editDescription(content), editPhasing(n?, content)
splitPhase(n, instructions), mergePhases(start, end, instructions?)
search(query), deepSearch(query)
repeatLast, stop
copyDescription, copyPhasing, copyBoth
conversation(content)
```

### End State: 4 Fluid Primitives
```swift
write(artifact: String, instructions: String?)
read(artifact: String, scope: String?)
search(query: String, depth: String?)
copy(artifact: String)
// conversation remains implicit
```

### Single Artifact: spec.md
Instead of separate `description.md` and `phasing.md`, we'll have a single `spec.md` containing both sections. This simplifies the mental model while keeping internal generation logic unchanged.

## Functional Constraints (Must Still Work)

Every existing capability MUST continue working through the new fluid primitives:

### Writing Operations
- ✅ "write the spec" → Creates both description and phasing from conversation history
- ✅ "write just the description" → Creates/updates only description section
- ✅ "write the phasing" → Creates/updates only phasing section
- ✅ "edit the description to be more technical" → Regenerates description with instruction
- ✅ "change phase 3 to include testing" → Targeted phase edit
- ✅ "split phase 2 into frontend and backend" → Phase splitting
- ✅ "merge phases 5 through 7" → Phase merging (up to 5 phases)
- ✅ "rewrite the phasing with smaller phases" → Full regeneration with instruction

### Reading Operations
- ✅ "read the spec" → Reads entire spec.md
- ✅ "read the description" → Reads just description section
- ✅ "read the phasing" → Reads just phasing section
- ✅ "read phase 4" → Reads specific phase
- ✅ "what's in phase 2?" → Extracts and reads phase 2

### Search Operations
- ✅ "search for swift concurrency" → Shallow web search
- ✅ "deep research kubernetes patterns" → Deep research mode
- ✅ "look up X" → Recognized as search

### Utility Operations
- ✅ "copy the spec" → Copies entire spec to clipboard
- ✅ "copy just the phasing" → Copies phasing section
- ✅ General conversation → Catch-all for discussion

### Removed Operations
- ❌ repeatLast → Deprecated
- ❌ stop → Deprecated

## Implementation Phasing

### Phase 1: Foundation - Artifact Consolidation
**Goal:** Create unified spec.md while maintaining backward compatibility

**Tasks:**
1. Update ArtifactManager to support spec.md (read/write both sections)
2. Add migration logic: check for legacy files, auto-merge on first access
3. Update AssistantClient to generate spec.md format (keeping internal prompts)
4. Create comprehensive test suite for spec.md operations
5. Test backward compatibility with existing description.md/phasing.md

**Validation:**
- All existing tests pass
- Can read old format, write new format
- Voice feedback remains unchanged ("Writing description..." then "Writing phasing...")

### Phase 2: Router Intelligence
**Goal:** Add fluid action recognition alongside discrete actions

**Tasks:**
1. Define FluidAction enum with 4 primitives
2. Update Router prompt to recognize natural language patterns
3. Add dual routing: try fluid first, fall back to discrete
4. Log all routing decisions for analysis
5. Create test corpus mapping natural language to expected routes

**Validation:**
- 100+ test cases for natural language inputs
- All old keywords still work
- New natural patterns route correctly

### Phase 3: Unified Write Handler
**Goal:** Consolidate all write operations through single handler

**Tasks:**
1. Create `executeWrite(artifact, instructions?)` in Orchestrator
2. Implement smart content loading (full doc for edits, history for creation)
3. Add instruction-aware generation (edit vs create vs transform)
4. Route all write-family actions through unified handler
5. Preserve atomic write guarantees and backups

**Validation:**
- Split/merge operations work correctly
- Targeted edits preserve unchanged content
- Generation from conversation history unchanged

### Phase 4: Unified Read Handler
**Goal:** Consolidate read operations with scope extraction

**Tasks:**
1. Create `executeRead(artifact, scope?)` in Orchestrator
2. Implement scope extraction using LLM when needed
3. Handle section extraction (description vs phasing vs specific phase)
4. Update TTS flow to work with extracted content
5. Test partial read scenarios

**Validation:**
- Can read full spec or sections
- Phase extraction works correctly
- TTS output unchanged

### Phase 5: Complete Migration
**Goal:** Remove discrete action code paths

**Tasks:**
1. Remove old discrete action handlers
2. Update Router to only use fluid primitives
3. Clean up ProposedAction enum
4. Update all logging and error messages
5. Final test suite execution

**Validation:**
- All functionality preserved
- Simpler codebase
- Natural language inputs work

### Phase 6: Polish & Optimization
**Goal:** Refine the experience based on testing

**Tasks:**
1. Tune Router prompts based on logged routing decisions
2. Optimize LLM prompts for common transformations
3. Add helpful suggestions in conversation mode
4. Document new interaction patterns
5. Create demo video script showing natural usage

**Validation:**
- Routing accuracy > 95%
- User feedback positive
- Performance unchanged or better

## Testing Strategy

### Existing Test Infrastructure
The codebase includes comprehensive routing tests in `Tests/` that we'll leverage:
- `RouterTests.swift` - Tests routing decisions
- `SplitMergeTestRunner.swift` - Tests complex transformations
- Test corpus with various user inputs

### Test Execution Plan
1. **Before each phase:** Run full test suite, establish baseline
2. **During development:** Add new tests for fluid patterns
3. **After each phase:** Ensure all tests still pass
4. **Integration tests:** Test natural conversation flows
5. **Performance tests:** Ensure no degradation in response time

### Key Test Scenarios
```swift
// Natural language that must work
"merge the last two phases"
"split phase 3 into smaller chunks"
"make the description more technical"
"read me what's in phase 5"
"rewrite everything but keep the same structure"
"edit phase 2 to add testing requirements"
```

## Success Criteria

1. **Functionality:** All 18 original actions work through 4 primitives
2. **Simplicity:** Codebase reduced by ~40% LOC in routing/orchestration
3. **Fluidity:** Users can speak naturally without memorizing keywords
4. **Performance:** No degradation in response time
5. **Reliability:** All existing tests pass, plus new natural language tests
6. **Migration:** Seamless upgrade for existing users with old artifacts

## Risk Mitigation

### Risk 1: Complex Transformations Less Precise
**Mitigation:** Keep specialized prompts for split/merge operations internally, just remove the rigid routing layer.

### Risk 2: Router Misclassification
**Mitigation:** Run both systems in parallel initially, log differences, tune based on real usage.

### Risk 3: Users Don't Discover Features
**Mitigation:** Add contextual hints in conversation mode, create demonstration videos.

### Risk 4: Breaking Changes
**Mitigation:** Comprehensive test suite, gradual rollout, backward compatibility mode.

## Implementation Notes

- Each phase should be completed in a single Claude Code session
- Tests should be run after each phase to ensure no regression
- The system should remain functional after each phase (no breaking intermediate states)
- Voice feedback phrases remain unchanged to avoid user confusion
- All file operations remain atomic with backup creation

## Appendix: Natural Language Mapping Examples

```
User Says                           → Routes To
"write everything"                  → write("spec", null)
"update the description"            → write("description", "update")
"merge phases 2 and 3"              → write("phasing", "merge phases 2 and 3")
"split the third phase"             → write("phasing", "split phase 3")
"read the whole thing"              → read("spec", null)
"what's phase 5 about?"             → read("phasing", "phase 5")
"search for swift async"            → search("swift async", null)
"deep dive into kubernetes"         → search("kubernetes", "deep")
```