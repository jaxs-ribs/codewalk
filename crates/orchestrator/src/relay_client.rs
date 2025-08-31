use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[derive(Clone, Debug)]
pub struct RelayConfig {
    pub ws: String,
    pub sid: String,
    pub tok: String,
    pub hb_secs: u64,
}

#[derive(Debug, Clone)]
pub enum RelayEvent {
    Status(String),
    Frame(String),
    PeerJoined(String),
    PeerLeft(String),
    SessionKilled,
    Error(String),
}

pub async fn start(config: RelayConfig) -> Result<mpsc::Receiver<RelayEvent>> {
    let (tx, rx) = mpsc::channel::<RelayEvent>(100);
    let cfg = config.clone();

    tokio::spawn(async move {
        let _ = tx.send(RelayEvent::Status(format!(
            "Connecting to relay {}",
            cfg.ws
        ))).await;

        match connect_async(&cfg.ws).await {
            Ok((ws_stream, _)) => {
                let (write, mut read) = ws_stream.split();

                // Send hello
                let hello = json!({
                    "type": "hello",
                    "s": cfg.sid,
                    "t": cfg.tok,
                    "r": "workstation"
                })
                .to_string();
                let write = std::sync::Arc::new(tokio::sync::Mutex::new(write));
                {
                    let mut guard = write.lock().await;
                    if let Err(e) = guard.send(Message::Text(hello)).await {
                        let _ = tx
                            .send(RelayEvent::Error(format!("send hello failed: {}", e)))
                            .await;
                        return;
                    }
                }

                let _ = tx.send(RelayEvent::Status("Sent hello".into())).await;

                // Heartbeat
                let hb_secs = cfg.hb_secs.max(5);
                let write_for_hb = write.clone();
                tokio::spawn(async move {
                    loop {
                        tokio::time::sleep(std::time::Duration::from_secs(hb_secs)).await;
                        let mut guard = write_for_hb.lock().await;
                        if guard
                            .send(Message::Text("{\"type\":\"hb\"}".to_string()))
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                });

                // Read loop
                while let Some(msg) = read.next().await {
                    match msg {
                        Ok(Message::Text(text)) => {
                            // Try to parse control envelopes
                            if let Ok(v) = serde_json::from_str::<Value>(&text) {
                                if let Some(t) = v.get("type").and_then(|s| s.as_str()) {
                                    match t {
                                        "hello-ack" => {
                                            let _ = tx.send(RelayEvent::Status("hello-ack".into())).await;
                                        }
                                        "peer-joined" => {
                                            let who = v
                                                .get("role")
                                                .and_then(|s| s.as_str())
                                                .unwrap_or("peer");
                                            let _ = tx.send(RelayEvent::PeerJoined(who.to_string())).await;
                                        }
                                        "peer-left" => {
                                            let who = v
                                                .get("role")
                                                .and_then(|s| s.as_str())
                                                .unwrap_or("peer");
                                            let _ = tx.send(RelayEvent::PeerLeft(who.to_string())).await;
                                        }
                                        "session-killed" => {
                                            let _ = tx.send(RelayEvent::SessionKilled).await;
                                            break;
                                        }
                                        "frame" => {
                                            // Extract inner frame (text). If it's JSON and is a note, send ack back.
                                            if let Some(frame_str) = v.get("frame").and_then(|s| s.as_str()) {
                                                let _ = tx.send(RelayEvent::Frame(frame_str.to_string())).await;
                                                if let Ok(inner) = serde_json::from_str::<Value>(frame_str) {
                                                    let inner_type = inner.get("type").and_then(|s| s.as_str());
                                                    if matches!(inner_type, Some("note") | Some("user_text")) {
                                                        // Best-effort ack
                                                        let reply_to = inner
                                                            .get("id")
                                                            .and_then(|s| s.as_str())
                                                            .unwrap_or("");
                                                        let ack = json!({
                                                            "type": "ack",
                                                            "replyTo": reply_to,
                                                            "text": "received"
                                                        })
                                                        .to_string();
                                                        let mut guard = write.lock().await;
                                                        let _ = guard.send(Message::Text(ack)).await;
                                                    }
                                                }
                                            }
                                        }
                                        _ => {
                                            let _ = tx.send(RelayEvent::Status(format!("msg:{}", t))).await;
                                        }
                                    }
                                } else {
                                    // Unknown JSON; pass through
                                    let _ = tx.send(RelayEvent::Frame(text)).await;
                                }
                            } else {
                                // Plain text
                                let _ = tx.send(RelayEvent::Frame(text)).await;
                            }
                        }
                        Ok(Message::Binary(b)) => {
                            let _ = tx
                                .send(RelayEvent::Status(format!("binary {} bytes", b.len())))
                                .await;
                        }
                        Ok(Message::Close(_)) => {
                            let _ = tx.send(RelayEvent::Status("closed".into())).await;
                            break;
                        }
                        Err(e) => {
                            let _ = tx.send(RelayEvent::Error(format!("ws error: {}", e))).await;
                            break;
                        }
                        _ => {}
                    }
                }
            }
            Err(e) => {
                let _ = tx
                    .send(RelayEvent::Error(format!("connect failed: {}", e)))
                    .await;
            }
        }
    });

    Ok(rx)
}

pub fn load_config_from_env() -> Result<Option<RelayConfig>> {
    let ws = std::env::var("RELAY_WS_URL").unwrap_or_else(|_| "ws://127.0.0.1:3001/ws".to_string());
    let sid = match std::env::var("RELAY_SESSION_ID") {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };
    let tok = match std::env::var("RELAY_TOKEN") {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };
    let hb_secs = std::env::var("RELAY_HB_SECS").ok().and_then(|s| s.parse().ok()).unwrap_or(20);
    Ok(Some(RelayConfig { ws, sid, tok, hb_secs }))
}
