use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

const EXPL: &str = "\x1b[35m"; // magenta
const RESET: &str = "\x1b[0m";

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    // Inputs via env: DEMO_WS, DEMO_SID, DEMO_TOK, DEMO_SEED(optional)
    let ws = std::env::var("DEMO_WS").context("DEMO_WS not set")?;
    let sid = std::env::var("DEMO_SID").context("DEMO_SID not set")?;
    let tok = std::env::var("DEMO_TOK").context("DEMO_TOK not set")?;
    let seed = std::env::var("DEMO_SEED").unwrap_or_else(|_| "demo".to_string());

    // Connect as phone
    println!("{}Phone connects to relay and authenticates with hello{}", EXPL, RESET);
    let (ws2, _) = connect_async(&ws).await.context("WS connect failed")?;
    let (mut w2, mut r2) = ws2.split();
    let hello = json!({"type":"hello","s":sid,"t":tok,"r":"phone"});
    w2.send(Message::Text(hello.to_string())).await?;
    println!("[phone] -> hello");
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_secs(2), r2.next()).await {
        print_classified("phone", &t);
    } else {
        anyhow::bail!("phone did not receive hello-ack");
    }

    // 1) Send a note(id=seed-p1)
    println!("{}Phone sends an app JSON 'note' with an id to workstation{}", EXPL, RESET);
    let p1_id = format!("{}-p1", seed);
    let note = json!({"type":"note","id":p1_id,"text":"hello from phone"});
    w2.send(Message::Text(note.to_string())).await?;
    println!("[phone] -> app {note}");

    // 2) Await workstation ack(replyTo=p1)
    println!("{}Phone waits for an 'ack' referencing its note (replyTo){}", EXPL, RESET);
    let got_ack = wait_for_frame_json(&mut r2, |j| j.get("replyTo").and_then(|s| s.as_str()) == Some(p1_id.as_str())).await;
    if !got_ack { anyhow::bail!("phone did not get workstation ack"); }
    println!("[phone] <- app replyTo={}", p1_id);

    // 3) Await workstation note(id=seed-w2) then reply ack
    println!("{}Phone waits for workstation 'note' then replies with an 'ack' referencing it{}", EXPL, RESET);
    let w2_id = format!("{}-w2", seed);
    let got_w2 = wait_for_frame_json(&mut r2, |j| j.get("id").and_then(|s| s.as_str()) == Some(w2_id.as_str())).await;
    if !got_w2 { anyhow::bail!("phone did not get workstation note"); }
    println!("[phone] <- app id={} (workstation)", w2_id);
    let ack = json!({"type":"ack","id":format!("{}-p2", seed),"replyTo":w2_id,"text":"pong from phone"});
    w2.send(Message::Text(ack.to_string())).await?;
    println!("[phone] -> app {ack}");

    Ok(())
}

fn print_classified(label: &str, text: &str) {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(text) {
        match v.get("type").and_then(|t| t.as_str()).unwrap_or("") {
            "hello-ack" => println!("[{}] <- [server] hello-ack", label),
            "peer-joined" => println!("[{}] <- [server] peer-joined(role={})", label, v.get("role").and_then(|s| s.as_str()).unwrap_or("?")),
            "frame" => {
                if let Some(f) = v.get("frame").and_then(|s| s.as_str()) { println!("[{}] <- [relay] frame(payload={})", label, f); }
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
                            if let Ok(j) = serde_json::from_str::<serde_json::Value>(f) { if pred(&j) { return true; } }
                        }
                    }
                }
            }
            Ok(Some(Ok(_))) => {}
            Ok(Some(Err(_))) | Ok(None) | Err(_) => return false,
        }
    }
}
