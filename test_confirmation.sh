#!/bin/bash

echo "Testing confirmation handler fix..."
echo ""

# Kill any existing orchestrator
pkill -f "target/release/codewalk" 2>/dev/null
pkill -f "target/debug/codewalk" 2>/dev/null
sleep 1

# Start orchestrator in background with logging
echo "Starting orchestrator..."
RUST_LOG=orchestrator=debug ./target/release/codewalk 2>&1 | tee test_confirmation_output.log &
ORCH_PID=$!
sleep 2

# Check if it started
if ! ps -p $ORCH_PID > /dev/null; then
    echo "ERROR: Orchestrator failed to start"
    cat test_confirmation_output.log
    exit 1
fi

echo "Orchestrator started with PID: $ORCH_PID"
echo ""

# Monitor the log file
echo "Monitoring latest log file..."
LATEST_LOG=$(ls -t logs/orchestrator_*.log | head -1)
echo "Log file: $LATEST_LOG"
echo ""

# Tail the log in background
tail -f "$LATEST_LOG" &
TAIL_PID=$!

echo "Test sequence:"
echo "1. Type a command to trigger Claude (e.g., 'help me with a test')"
echo "2. When asked for confirmation, type 'yes' to test ambiguous response"
echo "3. When re-prompted, type 'continue' or 'new'"
echo ""
echo "Press Ctrl+C to stop the test"

# Wait for user to stop
trap "kill $ORCH_PID $TAIL_PID 2>/dev/null; exit" INT
wait