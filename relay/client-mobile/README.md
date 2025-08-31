Headless Phone Client

This binary acts as a headless "phone" that connects to the relay server, sends a `user_text` message, and waits for the workstation to acknowledge it. It is used by the E2E runner but can be run manually for debugging.

Build

    cargo build -p relay-client-mobile --bin relay-phone-bot

Run

    RELAY_WS_URL=ws://127.0.0.1:3001/ws \
    RELAY_SESSION_ID=devsession0001 \
    RELAY_TOKEN=devtoken0001x \
    BOT_TEXT='build a small cli tool please' \
    cargo run -p relay-client-mobile --bin relay-phone-bot

If the workstation (orchestrator) is connected to the same relay session, the bot prints success after receiving an `ack`. It exits non‑zero if no ack is seen within a short timeout.

