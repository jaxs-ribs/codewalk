#!/bin/bash

echo "Testing log persistence..."

# Kill any existing orchestrator
pkill -f codewalk 2>/dev/null

# Start orchestrator in background
echo "Starting orchestrator..."
./target/debug/codewalk &
PID=$!

# Wait for it to start
sleep 3

# Send a test command via echo (simulating user input)
echo "Testing logs - this should appear in the logs" | nc localhost 8080 2>/dev/null || true

# Wait a bit for logs to be written
sleep 5

# Gracefully stop
kill -TERM $PID 2>/dev/null
wait $PID 2>/dev/null

echo "Checking for session logs..."
latest_session=$(ls -t artifacts/ | head -1)
if [ -n "$latest_session" ]; then
    echo "Latest session: $latest_session"
    echo "Contents:"
    ls -la "artifacts/$latest_session/"
    
    if [ -f "artifacts/$latest_session/logs.json" ]; then
        echo "✓ logs.json found"
        echo "First few lines:"
        head -5 "artifacts/$latest_session/logs.json"
    else
        echo "✗ No logs.json found"
    fi
    
    if [ -f "artifacts/$latest_session/logs.txt" ]; then
        echo "✓ logs.txt found"
        echo "First few lines:"
        head -5 "artifacts/$latest_session/logs.txt"
    else
        echo "✗ No logs.txt found"
    fi
else
    echo "✗ No session found in artifacts/"
fi