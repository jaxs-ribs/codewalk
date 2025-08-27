# Relay System

A high-performance WebSocket relay system using Redis pub/sub for message routing between paired clients.

## Components

- **server**: WebSocket server with Redis-backed session management
- **client-workstation**: Desktop client that generates QR codes for pairing
- **client-mobile**: Library for embedding in mobile apps (iOS/Android)
- **tests**: Comprehensive integration test suite

## Quick Start

### Run Tests

```bash
./run-test.sh
```

This will:
1. Start Redis (if needed)
2. Start the relay server
3. Run the complete integration test suite
4. Clean up afterwards

### Manual Testing

```bash
# Terminal 1: Start server
cargo run --release --bin relay-server

# Terminal 2: Start workstation client
cargo run --release --bin relay-workstation

# The workstation will display a QR code for mobile pairing
```

## Performance

The relay system handles:
- **6,000+ messages/second** under load
- **50+ concurrent client pairs**
- **Sub-millisecond latency** in optimal conditions
- **90% message delivery rate** under stress

## Requirements

- Rust 1.70+
- Redis 6.0+

## HTTP API

- `POST /api/register` → returns `{ sessionId, token, ws, ttl, qrDataUrl, qrPayload }` where `qrPayload` is `{ u, s, t }`.
- `DELETE /api/session/:id` → explicitly kills the session (returns 204 on success, 404 if missing).

## WebSocket Contract

- Hello: `{ "type":"hello", "s":"<sessionId>", "t":"<token>", "r":"workstation|phone" }` → `{"type":"hello-ack"}`
- Relay frame: `{ "type":"frame", "sid", "fromRole", "at", "frame", "b64" }`
- Peer notifications: `{"type":"peer-joined"}`, `{"type":"peer-left"}`
- Heartbeat: clients send `{"type":"hb"}` periodically; server refreshes session TTL and may reply `{"type":"hb-ack"}`
- Session killed: server publishes `{"type":"session-killed"}` and closes connections

## Environment

- `PORT` (default `3001`)
- `REDIS_URL` (default `redis://127.0.0.1:6379`)
- `PUBLIC_WS_URL` (default `ws://localhost:{PORT}/ws`)
- `SESSION_IDLE_SECS` (default `7200`): refresh on any activity (hello, frame, heartbeat)
- `HEARTBEAT_INTERVAL_SECS` (default `30`): heartbeat interval expected from clients
