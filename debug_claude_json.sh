#!/bin/bash

# Debug script to see raw Claude JSON output

echo "Testing Claude JSON output directly..."
echo "This will show raw JSON from Claude to help debug parsing"
echo ""

# Create a test directory if it doesn't exist
TEST_DIR="/tmp/claude_test"
mkdir -p "$TEST_DIR"

# Run Claude with a simple prompt and capture output
echo "Running Claude with streaming JSON output..."
echo ""

cd "$TEST_DIR"
claude -p "Just say hello" --output-format stream-json --verbose 2>&1 | tee claude_output.log

echo ""
echo "Output saved to: $TEST_DIR/claude_output.log"
echo ""
echo "First 20 lines of JSON output:"
head -20 "$TEST_DIR/claude_output.log"