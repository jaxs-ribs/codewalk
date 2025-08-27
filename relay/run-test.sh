#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}   RELAY SYSTEM TEST SUITE${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check dependencies
if ! command -v redis-cli &> /dev/null; then
    echo -e "${RED}Error: Redis is not installed${NC}"
    echo "Please install Redis:"
    echo "  macOS: brew install redis"
    echo "  Linux: sudo apt install redis-server"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Error: Rust/Cargo is not installed${NC}"
    exit 1
fi

# Start Redis if not running
if ! redis-cli ping &> /dev/null; then
    echo "Starting Redis..."
    redis-server --daemonize yes --port 6379 --save "" --appendonly no
    sleep 1
    REDIS_STARTED=1
else
    echo -e "${GREEN}✓ Redis is running${NC}"
    REDIS_STARTED=0
fi

# Build everything
echo ""
echo "Building relay system..."
cargo build --release -p relay-server -p relay-tests 2>/dev/null

# Start server if not running
if ! curl -s http://localhost:3001/health > /dev/null 2>&1; then
    echo "Starting relay server..."
    ../target/release/relay-server > /tmp/relay-server.log 2>&1 &
    SERVER_PID=$!
    sleep 2
    
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Server started${NC}"
    else
        echo -e "${RED}Failed to start server${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Server is running${NC}"
    SERVER_PID=""
fi

# Run tests
echo ""
echo "Running integration tests..."
echo "================================"
../target/release/relay-test

# Cleanup
echo ""
if [ ! -z "$SERVER_PID" ]; then
    echo "Stopping relay server..."
    kill $SERVER_PID 2>/dev/null || true
fi

if [ "$REDIS_STARTED" == "1" ]; then
    echo "Stopping Redis..."
    redis-cli shutdown 2>/dev/null || true
fi

echo -e "${GREEN}Test complete!${NC}"