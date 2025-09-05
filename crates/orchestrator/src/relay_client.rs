use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::sync::{mpsc, broadcast};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use once_cell::sync::OnceCell;

#[derive(Clone, Debug)]
pub struct RelayConfig {
    pub ws: String,
    pub sid: String,
    pub tok: String,
    pub hb_secs: u64,
}

#[cfg_attr(not(feature = "tui"), allow(dead_code))]
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
    let (tx, rx) = mpsc::channel::<RelayEvent>(200);
    // Broadcast channel for outbound frames; per-connection receivers subscribe()
    let (out_tx, _): (broadcast::Sender<String>, broadcast::Receiver<String>) = broadcast::channel(200);
    // Stash sender globally for simple access without changing callers
    let _ = OUT_SENDER.set(out_tx);
    let cfg = config.clone();

    tokio::spawn(async move {
        let mut attempt: u32 = 0;
        loop {
            attempt += 1;
            let _ = tx.send(RelayEvent::Status(format!("connecting (attempt {}): {}", attempt, cfg.ws))).await;
            match connect_async(&cfg.ws).await {
                Ok((ws_stream, _)) => {
                    let (write, mut read) = ws_stream.split();
                    let write = std::sync::Arc::new(tokio::sync::Mutex::new(write));
                    // hello
                    let hello = json!({ "type":"hello", "s": cfg.sid, "t": cfg.tok, "r": "workstation" }).to_string();
                    if write.lock().await.send(Message::Text(hello)).await.is_err() { continue; }
                    let _ = tx.send(RelayEvent::Status("hello-ack? waiting".into())).await;

                    // Heartbeat task
                    let hb_secs = cfg.hb_secs.max(5);
                    let write_for_hb = write.clone();
                    let hb_task = tokio::spawn(async move {
                        loop {
                            tokio::time::sleep(std::time::Duration::from_secs(hb_secs)).await;
                            let mut guard = write_for_hb.lock().await;
                            if guard.send(Message::Text("{\"type\":\"hb\"}".to_string())).await.is_err() { break; }
                        }
                    });

                    // Outbound sender task: forward app frames to websocket
                    let write_for_out = write.clone();
                    // subscribe to outbound frames for this connection
                    let mut out_rx = OUT_SENDER.get().unwrap().subscribe();
                    let send_task = tokio::spawn(async move {
                        loop {
                            match out_rx.recv().await {
                                Ok(frame) => {
                                    let mut guard = write_for_out.lock().await;
                                    if guard.send(Message::Text(frame)).await.is_err() {
                                        break;
                                    }
                                }
                                Err(broadcast::error::RecvError::Closed) => break,
                                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                            }
                        }
                    });

                    // Read loop
                    while let Some(msg) = read.next().await {
                        match msg {
                            Ok(Message::Text(text)) => {
                                if let Ok(v) = serde_json::from_str::<Value>(&text) {
                                    if let Some(t) = v.get("type").and_then(|s| s.as_str()) {
                                        match t {
                                            "hello-ack" => { let _ = tx.send(RelayEvent::Status("hello-ack".into())).await; }
                                            "peer-joined" => { let who = v.get("role").and_then(|s| s.as_str()).unwrap_or("peer"); let _ = tx.send(RelayEvent::PeerJoined(who.to_string())).await; }
                                            "peer-left" => { let who = v.get("role").and_then(|s| s.as_str()).unwrap_or("peer"); let _ = tx.send(RelayEvent::PeerLeft(who.to_string())).await; }
                                            "session-killed" => { let _ = tx.send(RelayEvent::SessionKilled).await; break; }
                                            "frame" => {
                                                if let Some(frame_str) = v.get("frame").and_then(|s| s.as_str()) {
                                                    let _ = tx.send(RelayEvent::Frame(frame_str.to_string())).await;
                                                    if let Ok(inner) = serde_json::from_str::<Value>(frame_str) {
                                                        let inner_type = inner.get("type").and_then(|s| s.as_str());
                                                        if matches!(inner_type, Some("note") | Some("user_text")) {
                                                            let reply_to = inner.get("id").and_then(|s| s.as_str()).unwrap_or("");
                                                            let ack = json!({"type":"ack","replyTo":reply_to,"text":"received"}).to_string();
                                                            let mut guard = write.lock().await; let _ = guard.send(Message::Text(ack)).await;
                                                        }
                                                    }
                                                }
                                            }
                                            _ => { let _ = tx.send(RelayEvent::Status(format!("msg:{}", t))).await; }
                                        }
                                    } else { let _ = tx.send(RelayEvent::Frame(text)).await; }
                                } else { let _ = tx.send(RelayEvent::Frame(text)).await; }
                            }
                            Ok(Message::Binary(b)) => { let _ = tx.send(RelayEvent::Status(format!("binary {} bytes", b.len()))).await; }
                            Ok(Message::Close(_)) => { let _ = tx.send(RelayEvent::Status("closed".into())).await; break; }
                            Err(e) => { let _ = tx.send(RelayEvent::Error(format!("ws error: {}", e))).await; break; }
                            _ => {}
                        }
                    }
                    hb_task.abort();
                    send_task.abort();
                    // fallthrough to reconnect
                }
                Err(e) => { let _ = tx.send(RelayEvent::Error(format!("connect failed: {}", e))).await; }
            }
            // Backoff before reconnect
            let delay = std::cmp::min(30, 1 << std::cmp::min(5, attempt)); // 2,4,8,16,32→cap at 30
            let _ = tx.send(RelayEvent::Status(format!("reconnecting in {}s", delay))).await;
            tokio::time::sleep(std::time::Duration::from_secs(delay as u64)).await;
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

// Minimal global sender to emit frames over the relay socket from elsewhere in the app
static OUT_SENDER: OnceCell<broadcast::Sender<String>> = OnceCell::new();

/// Convenience function to connect to relay if configured
pub async fn connect_if_configured() -> Option<mpsc::Receiver<RelayEvent>> {
    match load_config_from_env() {
        Ok(Some(config)) => {
            match start(config).await {
                Ok(rx) => Some(rx),
                Err(e) => {
                    eprintln!("Failed to start relay: {}", e);
                    None
                }
            }
        }
        _ => None
    }
}

pub fn send_frame(text: String) {
    if let Some(tx) = OUT_SENDER.get() {
        let _ = tx.send(text);
    }
}
