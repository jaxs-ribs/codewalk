# Test Suite Notes

## Known Issues

### 1. Response Message Mismatch on Read
**Issue:** When reading phasing/description, the test shows `Response: "Reading phasing..."` but the actual response is the full artifact content.

**Example:**
```
▶️  Step 3/3: "read the phasing"
💬 Response: "Reading phasing..."
```

But then the full phasing markdown is spoken/displayed.

**Impact:** Minor - cosmetic only. The response message string doesn't match what's actually returned.

**Fix:** Response should probably be empty or "Read complete" after the content is spoken.

---

### 2. Log Verbosity in Output
**Issue:** Colored ANSI log codes still appear in test output despite grep filter.

**Current filter:**
```bash
grep -vE "^\[2m\[.*\] \[38;5"
```

**Impact:** Minor - output is slightly noisy but readable.

**Fix:** Improve regex or suppress logs at source during test mode.

---

### 3. Artifact Persistence Across Tests
**Issue:** Artifacts (description.md, phasing.md) persist across test runs. Tests don't start with clean slate.

**Example:** Router test shows description.md exists even though it was written in previous test.

**Impact:** Minor - doesn't affect correctness, but could mask issues if tests depended on fresh state.

**Fix:** Either:
- Clean artifacts before each test run
- Use separate test artifact directories
- Document that tests share state

---

## What's Working Well

✅ **Router accuracy** - 100% correct action detection
✅ **Multi-pass generation** - Both passes complete, output gets refined
✅ **Timing** - Fast tests (2.8-8.2s each, ~22s total suite)
✅ **Real artifacts** - Tests write valid files with reasonable sizes
✅ **Edit workflow** - Successfully regenerates with new requirements
✅ **Cost efficiency** - ~20 API calls for full suite

---

## Recommendations

### High Priority
None - suite is production-ready

### Nice to Have
1. Add artifact cleanup between tests (`rm artifacts/*.md` before each run)
2. Improve log filtering for cleaner output
3. Fix response message on read actions