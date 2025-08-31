use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    // Inputs via env or args: RELAY_WS_URL / DEMO_WS, RELAY_SESSION_ID / DEMO_SID, RELAY_TOKEN / DEMO_TOK, BOT_TEXT
    let ws = std::env::var("RELAY_WS_URL").or_else(|_| std::env::var("DEMO_WS")).context("RELAY_WS_URL/DEMO_WS not set")?;
    let sid = std::env::var("RELAY_SESSION_ID").or_else(|_| std::env::var("DEMO_SID")).context("RELAY_SESSION_ID/DEMO_SID not set")?;
    let tok = std::env::var("RELAY_TOKEN").or_else(|_| std::env::var("DEMO_TOK")).context("RELAY_TOKEN/DEMO_TOK not set")?;
    let text = if let Some(t) = std::env::var("BOT_TEXT").ok() { t } else {
        let args = std::env::args().skip(1).collect::<Vec<_>>();
        if args.is_empty() { "hello from phone-bot".to_string() } else { args.join(" ") }
    };

    let (ws_stream, _) = connect_async(&ws).await.context("WS connect failed")?;
    let (mut write, mut read) = ws_stream.split();

    // hello
    let hello = json!({"type":"hello","s":sid,"t":tok,"r":"phone"}).to_string();
    write.send(Message::Text(hello)).await?;

    // wait for hello-ack
    let _ack_ok = wait_for(&mut read, |v| v.get("type").and_then(|s| s.as_str()) == Some("hello-ack"), 5).await?;

    // optional wait-for-kill only
    if std::env::var("BOT_WAIT_KILL").unwrap_or_default() == "1" {
        eprintln!("\x1b[33m[bot]\x1b[0m waiting for session-killed…");
        let killed = wait_for(&mut read, |v| v.get("type").and_then(|s| s.as_str()) == Some("session-killed"), 10).await?;
        if !killed { anyhow::bail!("no session-killed"); }
        eprintln!("\x1b[32m[bot]\x1b[0m got session-killed");
        return Ok(());
    }

    // send user_text
    let ut = json!({"type":"user_text","text":text,"final":true,"source":"phone"}).to_string();
    write.send(Message::Text(ut)).await?;

    // wait for ack from workstation (wrapped in relay frame)
    let got_ack = wait_for(&mut read, |v| {
        if v.get("type").and_then(|s| s.as_str()) == Some("frame") {
            if let Some(frame) = v.get("frame").and_then(|s| s.as_str()) {
                if let Ok(inner) = serde_json::from_str::<Value>(frame) {
                    return inner.get("type").and_then(|s| s.as_str()) == Some("ack");
                }
            }
        }
        false
    }, 10).await?;
    if !got_ack { anyhow::bail!("no ack from workstation"); }
    eprintln!("\x1b[32m[bot]\x1b[0m ack received");

    Ok(())
}

async fn wait_for<R>(read: &mut R, pred: impl Fn(&Value) -> bool, timeout_secs: u64) -> Result<bool>
where
    R: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(timeout_secs);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() { return Ok(false); }
        match timeout(remaining, read.next()).await {
            Ok(Some(Ok(Message::Text(t)))) => {
                if let Ok(v) = serde_json::from_str::<Value>(&t) { if pred(&v) { return Ok(true); } }
            }
            Ok(Some(Ok(_))) => {}
            Ok(Some(Err(_))) | Ok(None) | Err(_) => return Ok(false),
        }
    }
}
