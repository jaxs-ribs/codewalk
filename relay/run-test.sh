#!/bin/bash

set -euo pipefail

# Resolve repo root relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

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

# Always start a fresh test server on an isolated port
TEST_PORT=${TEST_PORT:-3111}
export RELAY_BASE_URL=${RELAY_BASE_URL:-http://localhost:$TEST_PORT}
echo "Starting relay server on port $TEST_PORT (cargo run)..."
# Speed up lifecycle tests
export SESSION_IDLE_SECS=${SESSION_IDLE_SECS:-2}
export HEARTBEAT_INTERVAL_SECS=${HEARTBEAT_INTERVAL_SECS:-1}
export PORT=$TEST_PORT
export PUBLIC_WS_URL=${PUBLIC_WS_URL:-ws://localhost:$TEST_PORT/ws}

# Start the server via cargo run to avoid path/exec issues
(
  cd "$REPO_ROOT"
  RUST_LOG=${RUST_LOG:-relay_server=info} \
  cargo run --release -p relay-server > /tmp/relay-server.log 2>&1 &
  echo $! > /tmp/relay-server.cargo-pid
)
SERVER_PID=$(cat /tmp/relay-server.cargo-pid)

# Wait for health up to 10 seconds
for i in {1..20}; do
  if curl -s "$RELAY_BASE_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server started on $RELAY_BASE_URL${NC}"
    break
  fi
  sleep 0.5
done
if ! curl -s "$RELAY_BASE_URL/health" > /dev/null 2>&1; then
  echo -e "${RED}Failed to start server; see /tmp/relay-server.log${NC}"
  exit 1
fi

# Run tests
echo ""
echo "Running integration tests..."
echo "================================"
ONLY_ARG=${1:-}
if [ -n "$ONLY_ARG" ]; then
  echo "Running only test: $ONLY_ARG"
  export RUN_ONLY="$ONLY_ARG"
else
  echo "Running full test suite via cargo run..."
  export RUN_FULL_TESTS=1
fi
(
  cd "$REPO_ROOT"
  RUN_FULL_TESTS=${RUN_FULL_TESTS:-0} RELAY_BASE_URL="$RELAY_BASE_URL" cargo run --release -p relay-tests
)

# Cleanup
echo ""
if [ ! -z "${SERVER_PID}" ]; then
    echo "Stopping relay server..."
    kill "$SERVER_PID" 2>/dev/null || true
fi

if [ "$REDIS_STARTED" == "1" ]; then
    echo "Stopping Redis..."
    redis-cli shutdown 2>/dev/null || true
fi

echo -e "${GREEN}Test complete!${NC}"
