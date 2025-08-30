use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

const EXPL: &str = "\x1b[36m"; // cyan
const RESET: &str = "\x1b[0m";

#[tokio::main]
async fn main() -> Result<()> {
    // Inputs via env: DEMO_WS, DEMO_SID, DEMO_TOK, DEMO_SEED (optional)
    let ws = std::env::var("DEMO_WS").context("DEMO_WS not set")?;
    let sid = std::env::var("DEMO_SID").context("DEMO_SID not set")?;
    let tok = std::env::var("DEMO_TOK").context("DEMO_TOK not set")?;
    let seed = std::env::var("DEMO_SEED").unwrap_or_else(|_| "demo".to_string());

    // Connect as workstation
    println!("{}Workstation connects to relay and authenticates with hello{}", EXPL, RESET);
    let (ws1, _) = connect_async(&ws).await.context("WS connect failed")?;
    let (mut w1, mut r1) = ws1.split();
    let hello = json!({"type":"hello","s":sid,"t":tok,"r":"workstation"});
    w1.send(Message::Text(hello.to_string())).await?;
    println!("[workstation] -> hello");
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_secs(2), r1.next()).await {
        print_classified("workstation", &t);
    } else {
        anyhow::bail!("workstation did not receive hello-ack");
    }

    // Optional: observe peer-joined
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_secs(2), r1.next()).await {
        print_classified("workstation", &t);
    }

    // 1) Wait for phone note(id=seed-p1)
    println!("{}Phone will send an app JSON 'note' with an id; workstation waits to receive it{}", EXPL, RESET);
    let p1_id = format!("{}-p1", seed);
    let got_p1 = wait_for_frame_json(&mut r1, |j| j.get("id").and_then(|s| s.as_str()) == Some(p1_id.as_str())).await;
    if !got_p1 { anyhow::bail!("workstation did not get phone app JSON"); }
    println!("[workstation] <- app id={} (phone)", p1_id);

    // 2) Send ack referencing p1
    println!("{}Workstation replies with an 'ack' that references the phone note via replyTo{}", EXPL, RESET);
    let w1_id = format!("{}-w1", seed);
    let ack = json!({"type":"ack","id":w1_id,"replyTo":p1_id,"text":"ack from workstation"});
    w1.send(Message::Text(ack.to_string())).await?;
    println!("[workstation] -> app {ack}");

    // 3) Send a note(id=seed-w2) and await phone ack
    println!("{}Workstation sends a new 'note' (ping); expects phone to reply with an 'ack' (pong) referencing it{}", EXPL, RESET);
    let w2_id = format!("{}-w2", seed);
    let note = json!({"type":"note","id":w2_id,"text":"ping from workstation"});
    w1.send(Message::Text(note.to_string())).await?;
    println!("[workstation] -> app {note}");
    let got_ack = wait_for_frame_json(&mut r1, |j| j.get("replyTo").and_then(|s| s.as_str()) == Some(w2_id.as_str())).await;
    if !got_ack { anyhow::bail!("workstation did not receive phone ack"); }
    println!("[workstation] <- app reply observed");

    // Heartbeat (optional)
    println!("{}Workstation sends a heartbeat to refresh session TTL{}", EXPL, RESET);
    w1.send(Message::Text(json!({"type":"hb"}).to_string())).await.ok();
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(500), r1.next()).await { print_classified("workstation", &t); }

    Ok(())
}

fn print_classified(label: &str, text: &str) {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(text) {
        match v.get("type").and_then(|t| t.as_str()).unwrap_or("") {
            "hello-ack" => println!("[{}] <- [server] hello-ack", label),
            "peer-joined" => println!("[{}] <- [server] peer-joined(role={})", label, v.get("role").and_then(|s| s.as_str()).unwrap_or("?")),
            "hb-ack" => println!("[{}] <- [server] hb-ack", label),
            "frame" => {
                if let Some(f) = v.get("frame").and_then(|s| s.as_str()) {
                    println!("[{}] <- [relay] frame(payload={})", label, f);
                }
            }
            _ => println!("[{}] <- {}", label, text),
        }
    } else {
        println!("[{}] <- {}", label, text);
    }
}

async fn wait_for_frame_json<R>(r: &mut R, pred: impl Fn(&serde_json::Value) -> bool) -> bool
where
    R: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() { return false; }
        match timeout(remaining, r.next()).await {
            Ok(Some(Ok(Message::Text(t)))) => {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
                    if v.get("type").and_then(|s| s.as_str()) == Some("frame") {
                        if let Some(f) = v.get("frame").and_then(|s| s.as_str()) {
                            if let Ok(j) = serde_json::from_str::<serde_json::Value>(f) {
                                if pred(&j) { return true; }
                            }
                        }
                    }
                }
            }
            Ok(Some(Ok(_))) => {}
            Ok(Some(Err(_))) | Ok(None) | Err(_) => return false,
        }
    }
}
