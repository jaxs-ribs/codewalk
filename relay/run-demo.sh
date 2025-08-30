#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}   RELAY MINIMAL DEMO PIPELINE  ${NC}"
echo -e "${BLUE}================================${NC}"

if ! command -v redis-cli >/dev/null 2>&1; then
  echo -e "${RED}Redis is required (install via brew/apt).${NC}"; exit 1;
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo -e "${RED}Rust/Cargo is required.${NC}"; exit 1;
fi

# Start Redis if needed
if ! redis-cli ping >/dev/null 2>&1; then
  echo "Starting Redis..."
  redis-server --daemonize yes --port 6379 --save "" --appendonly no
  sleep 1
  REDIS_STARTED=1
else
  REDIS_STARTED=0
fi

# Build server and demo client
echo "Building server and demo..."
cargo build --release -p relay-server -p relay-client-workstation -p relay-client-mobile >/dev/null

DEMO_PORT=${DEMO_PORT:-3112}
export RELAY_BASE_URL=${RELAY_BASE_URL:-http://localhost:$DEMO_PORT}
export PORT=$DEMO_PORT
export PUBLIC_WS_URL=${PUBLIC_WS_URL:-ws://localhost:$DEMO_PORT/ws}
export SESSION_IDLE_SECS=${SESSION_IDLE_SECS:-10}
export HEARTBEAT_INTERVAL_SECS=${HEARTBEAT_INTERVAL_SECS:-2}

echo "Starting relay server on port $DEMO_PORT..."
(
  cd "$REPO_ROOT"
  RUST_LOG=${RUST_LOG:-relay_server=info} cargo run --release -p relay-server \
    > /tmp/relay-demo-server.log 2>&1 &
  echo $! > /tmp/relay-demo-server.pid
)
SERVER_PID=$(cat /tmp/relay-demo-server.pid)

# Wait for health
for i in {1..40}; do
  if curl -s "$RELAY_BASE_URL/health" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Server up at $RELAY_BASE_URL${NC}"
    break
  fi
  sleep 0.25
done
if ! curl -s "$RELAY_BASE_URL/health" >/dev/null 2>&1; then
  echo -e "${RED}Server failed to start; see /tmp/relay-demo-server.log${NC}"
  kill "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

echo "Preparing demo session..."
SESSION_JSON=/tmp/relay-demo-session.json
curl -s -X POST "$RELAY_BASE_URL/api/register" -o "$SESSION_JSON"
WS=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ws"])' "$SESSION_JSON")
SID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sessionId"])' "$SESSION_JSON")
TOK=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["token"])' "$SESSION_JSON")
SEED=${DEMO_SEED:-demo}
echo "Session: $SID"

echo "Running workstation + phone demos..."
(
  cd "$REPO_ROOT"
  DEMO_WS="$WS" DEMO_SID="$SID" DEMO_TOK="$TOK" DEMO_SEED="$SEED" \
    cargo run --release -p relay-client-workstation --bin relay-workstation-demo &
  W_PID=$!
  sleep 0.4
  DEMO_WS="$WS" DEMO_SID="$SID" DEMO_TOK="$TOK" DEMO_SEED="$SEED" \
    cargo run --release -p relay-client-mobile --bin relay-phone-demo
  wait $W_PID || true
)

echo "Shutting down..."
kill "$SERVER_PID" 2>/dev/null || true
if [ "$REDIS_STARTED" = "1" ]; then
  redis-cli shutdown 2>/dev/null || true
fi

echo -e "${GREEN}Demo complete.${NC}"
