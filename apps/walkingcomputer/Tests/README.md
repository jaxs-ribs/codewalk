# Test Suite

Automated tests for the Walking Computer agent.

## Running Tests

```bash
# Run specific test
./test-agent.sh basic
./test-agent.sh write_read
./test-agent.sh edit
./test-agent.sh router
./test-agent.sh empty

# Run all tests
./test-agent.sh all
```

## Test Coverage

| Test | Purpose | API Calls |
|------|---------|-----------|
| `basic` | Basic phasing generation | 3 (router + 2-pass) |
| `write_read` | Write then read workflow | 5 |
| `edit` | Edit existing phasing | 7 |
| `router` | Router command recognition | 4 (routing only) |
| `empty` | Empty conversation edge case | 2 |

## What Tests Verify

- ✅ Router correctly identifies actions (write/read/edit/copy)
- ✅ Multi-pass phasing generation works
- ✅ Artifacts are written to disk
- ✅ Edit flow regenerates with new requirements
- ✅ Read commands fetch and display artifacts
- ✅ Edge cases handled gracefully

## Cost Considerations

Each test uses real APIs (Groq for LLM, writes real artifacts). The `all` suite costs ~20 API calls total.

## Adding New Tests

Edit `Tests/TestRunner.swift` to add new test scripts:

```swift
static func myNewTest() -> (String, [String]) {
    return (
        "My Test Name",
        [
            "prompt 1",
            "prompt 2"
        ]
    )
}
```

Then add to `Tests/main.swift` switch statement.