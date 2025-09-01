#!/bin/bash

echo "Testing session-based logging..."

# Clean up any previous artifacts
rm -rf artifacts/

# Start the orchestrator in the background
echo "Starting orchestrator..."
./target/debug/codewalk &
ORCHESTRATOR_PID=$!

# Give it time to start
sleep 2

# Check if artifacts directory was created
if [ -d "artifacts" ]; then
    echo "✓ Artifacts directory created"
else
    echo "✗ Artifacts directory not created"
fi

# Kill the orchestrator
kill $ORCHESTRATOR_PID 2>/dev/null

echo "Test complete. Check artifacts/ directory for session logs."