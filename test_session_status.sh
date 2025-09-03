#!/bin/bash

# Test script for session management and status reporting
# This tests that the orchestrator properly tracks and reports session status

echo "=== Session Management Test ==="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clean up any previous test artifacts
echo "1. Cleaning up previous test artifacts..."
rm -rf artifacts/session_test_*
pkill -f "codewalk" 2>/dev/null
sleep 1

# Build the orchestrator if needed
echo "2. Building orchestrator..."
cargo build -p orchestrator 2>/dev/null || {
    echo -e "${RED}Failed to build orchestrator${NC}"
    exit 1
}

# Start orchestrator in background
echo "3. Starting orchestrator..."
./target/debug/orchestrator &
ORCH_PID=$!
sleep 2

# Check if orchestrator started
if ! ps -p $ORCH_PID > /dev/null; then
    echo -e "${RED}Orchestrator failed to start${NC}"
    exit 1
fi
echo -e "${GREEN}Orchestrator started (PID: $ORCH_PID)${NC}"

# Function to send a message to orchestrator via relay
send_message() {
    local message="$1"
    echo -e "${YELLOW}Sending: $message${NC}"
    
    # Use the phone bot to send message
    echo "$message" | ./target/debug/phone-bot 2>/dev/null || {
        # Fallback to direct relay if phone-bot not available
        curl -s -X POST http://localhost:8080/message \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$message\"}" > /dev/null
    }
    sleep 3
}

echo
echo "4. Testing session queries..."
echo "-------------------------------"

# Test 1: Query with no active session
echo -e "\n${YELLOW}Test 1: Query with no active session${NC}"
send_message "what's happening"
sleep 2

# Check artifacts directory for response
if [ -d "artifacts" ]; then
    echo -e "${GREEN}✓ Artifacts directory exists${NC}"
    
    # Look for session directories
    SESSION_COUNT=$(ls -d artifacts/session_* 2>/dev/null | wc -l)
    echo "  Found $SESSION_COUNT session directories"
fi

# Test 2: Start a Claude session
echo -e "\n${YELLOW}Test 2: Starting a Claude session${NC}"
send_message "help me write a hello world function"
echo "Waiting for session to start..."
sleep 10

# Test 3: Query during active session
echo -e "\n${YELLOW}Test 3: Query during active session${NC}"
send_message "what's the status"
sleep 3

# Check for active session metadata
ACTIVE_SESSION=$(ls -t artifacts/session_*/metadata.json 2>/dev/null | head -1)
if [ -n "$ACTIVE_SESSION" ]; then
    echo -e "${GREEN}✓ Found active session metadata${NC}"
    echo "  Session metadata:"
    cat "$ACTIVE_SESSION" | jq '.' 2>/dev/null || cat "$ACTIVE_SESSION"
fi

# Test 4: Wait for session to complete
echo -e "\n${YELLOW}Test 4: Waiting for session to complete...${NC}"
sleep 20

# Test 5: Query after session completes
echo -e "\n${YELLOW}Test 5: Query after session completion${NC}"
send_message "what was the previous session about"
sleep 3

# Check for completed session metadata
COMPLETED_SESSION=$(ls -t artifacts/session_*/metadata.json 2>/dev/null | head -1)
if [ -n "$COMPLETED_SESSION" ]; then
    STATUS=$(cat "$COMPLETED_SESSION" | jq -r '.status' 2>/dev/null || grep '"status"' "$COMPLETED_SESSION")
    if [[ "$STATUS" == *"completed"* ]]; then
        echo -e "${GREEN}✓ Session marked as completed${NC}"
    else
        echo -e "${RED}✗ Session not marked as completed${NC}"
    fi
fi

# Test 6: Check session logs
echo -e "\n${YELLOW}Test 6: Checking session logs${NC}"
LOG_FILES=$(find artifacts -name "logs.json" -o -name "logs.txt" 2>/dev/null)
if [ -n "$LOG_FILES" ]; then
    echo -e "${GREEN}✓ Session logs found:${NC}"
    echo "$LOG_FILES"
    
    # Check log content
    for log in $LOG_FILES; do
        LINE_COUNT=$(wc -l < "$log")
        echo "  $(basename $(dirname "$log"))/$(basename "$log"): $LINE_COUNT lines"
    done
else
    echo -e "${RED}✗ No session logs found${NC}"
fi

# Cleanup
echo
echo "7. Cleaning up..."
kill $ORCH_PID 2>/dev/null
wait $ORCH_PID 2>/dev/null

echo
echo "=== Test Summary ==="
echo "--------------------"

# Count results
TOTAL_SESSIONS=$(ls -d artifacts/session_* 2>/dev/null | wc -l)
COMPLETED_SESSIONS=$(grep -l '"status".*"completed"' artifacts/session_*/metadata.json 2>/dev/null | wc -l)

echo "Total sessions created: $TOTAL_SESSIONS"
echo "Completed sessions: $COMPLETED_SESSIONS"

if [ $TOTAL_SESSIONS -gt 0 ]; then
    echo -e "\n${GREEN}Session management test completed successfully!${NC}"
    echo
    echo "To examine the artifacts:"
    echo "  ls -la artifacts/"
    echo "  cat artifacts/session_*/metadata.json"
    echo "  cat artifacts/session_*/logs.txt"
else
    echo -e "\n${RED}No sessions were created during the test${NC}"
fi

echo
echo "Test complete."