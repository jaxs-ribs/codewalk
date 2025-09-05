#!/bin/bash

# Simulate sending a user_text message to the orchestrator

echo "Starting orchestrator with detailed logging..."
RUST_LOG=debug ./target/release/codewalk 2>&1 | tee test_run.log &
ORCH_PID=$!

sleep 3

echo "Sending test message via relay..."
# The orchestrator should be listening for relay messages
# We need to simulate what the relay would send

echo "Orchestrator PID: $ORCH_PID"

# Monitor the log
LATEST_LOG=$(ls -t logs/orchestrator_*.log | head -1)
echo "Monitoring log: $LATEST_LOG"

tail -f "$LATEST_LOG" &
TAIL_PID=$!

echo ""
echo "Now in the orchestrator TUI, type:"
echo "  'help me create a snake game with Claude'"
echo ""
echo "Watch the log to see what happens..."
echo "Press Ctrl+C to stop"

trap "kill $ORCH_PID $TAIL_PID 2>/dev/null; exit" INT
wait