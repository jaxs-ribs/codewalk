#!/bin/bash

# Test runner for Walking Computer agent
# Usage: ./test-agent.sh [test_name]
# Available tests: basic, dog_tinder, snake, all

set -e

TEST_NAME="${1:-basic}"

cd "$(dirname "$0")"

echo "🧪 Walking Computer Agent Test Runner"
echo "======================================"
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "❌ Error: .env file not found"
    echo "   Please create .env with GROQ_API_KEY and other required keys"
    exit 1
fi

# Collect all source files needed for testing
SOURCES=(
    # Core
    "Sources/Core/EnvConfig.swift"
    "Sources/Logger.swift"
    "Sources/Orchestrator.swift"
    "Sources/AssistantClient.swift"
    "Sources/Router.swift"
    "Sources/ArtifactManager.swift"
    "Sources/NetworkManager.swift"

    # TTS
    "Sources/TTS/TTSProtocol.swift"
    "Sources/TTS/MockTTSManager.swift"

    # Services (needed by Orchestrator)
    # Note: Skipping GroqTTSManager and ElevenLabsTTS - they have iOS dependencies
    # Tests use MockTTSManager instead
    "Sources/Search/SearchTypes.swift"
    "Sources/Search/SearchService.swift"
    "Sources/Search/PerplexitySearchService.swift"

    # Test infrastructure
    "Tests/TestRunner.swift"
    "Tests/main.swift"
)

# Build command
echo "🔨 Compiling test runner..."
COMPILE_OUTPUT=$(swiftc -parse-as-library -o test-runner "${SOURCES[@]}" 2>&1)
COMPILE_STATUS=$?

# Show only errors (not warnings)
echo "$COMPILE_OUTPUT" | grep -E "error:" || true

if [ $COMPILE_STATUS -eq 0 ] && [ -f test-runner ]; then
    echo "✅ Compilation successful"
    echo ""
    echo "▶️  Running test: $TEST_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Run the test and filter out verbose logs
    # Only show test output, not internal system logs
    ./test-runner "$TEST_NAME" 2>&1 | grep -vE "^\[2m\[.*\] \[38;5"

    # Cleanup
    rm -f test-runner
else
    echo ""
    echo "❌ Compilation failed. Trying alternative approach..."
    echo ""
    echo "You can run tests manually:"
    echo "  1. Open WalkingComputer.xcodeproj in Xcode"
    echo "  2. Add Tests/main.swift to a new macOS Command Line Tool target"
    echo "  3. Include the source files listed above"
    echo "  4. Build and run"
    exit 1
fi