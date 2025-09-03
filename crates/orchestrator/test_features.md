# Testing Session History, Caching, and Confirmation Message

## Test 1: Session History
1. Start a Claude Code session with any task
2. Wait for it to complete
3. Ask "What's happening?" - should describe the last session

## Test 2: Summary Caching  
1. Start a Claude Code session
2. Ask "What's happening?" twice quickly (within 10 seconds)
3. Check orchestrator logs - should show "Returning cached summary" for second query

## Test 3: Confirmation Message
1. Say a command like "help me fix the bug in the router"
2. Should hear confirmation: "Do you want me to start a Claude Code session for this? Yes or no"
3. Say "yes"
4. Should hear: "Starting Claude Code for: help me fix the bug in the router" (not just "Starting Claude Code session")
