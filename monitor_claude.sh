#!/bin/bash

echo "=== Monitoring Claude processes ==="
echo "Current Claude processes:"
ps aux | grep claude | grep -v grep | grep -v monitor_claude

echo -e "\nProcess IDs:"
pgrep -f "claude.*-p" || echo "No headless Claude sessions found"

echo -e "\nTo kill orphaned Claude processes:"
echo "pkill -f 'claude.*-p.*--dangerously-skip-permissions'"

echo -e "\nTo kill ALL Claude processes (except this one):"
echo "pkill -f 'claude' (use with caution!)"