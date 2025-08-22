#!/bin/bash

# Test script to verify Claude streaming JSON works

echo "Testing Claude streaming JSON implementation..."
echo "This will launch Claude with a simple prompt and check if logs appear"
echo ""

# Run the orchestrator with a test prompt
echo "Starting orchestrator..."
cd /Users/fresh/Documents/codewalk

# Build first
echo "Building project..."
cargo build --release

# Run with a simple test
echo ""
echo "Launching orchestrator with test prompt..."
echo "Press 'l' to launch Claude with prompt: 'What is 2+2?'"
echo "Watch the right pane for session logs"
echo "Press 'q' to quit"
echo ""

./target/release/orchestrator