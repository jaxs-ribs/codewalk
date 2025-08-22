#!/bin/bash

# Test launching Claude with a simple prompt
cd ~/Documents/walking-projects/first

echo "Testing Claude launch with headless mode..."
claude -p "Create a simple hello world JavaScript file" --add-dir . 2>&1 | head -20

echo -e "\n\nChecking if file was created..."
ls -la *.js 2>/dev/null || echo "No JS files created yet"