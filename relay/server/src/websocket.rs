use crate::{AppState, session::Session};
use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, Extension},
    response::IntoResponse,
};
use futures::{SinkExt, StreamExt};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, broadcast};
use tracing::{error, info, warn};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct HelloMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub s: String,
    pub t: String,
    pub r: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RelayMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub sid: String,
    #[serde(rename = "fromRole")]
    pub from_role: String,
    pub at: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frame: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b64: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct HelloAck {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(rename = "sessionId")]
    pub session_id: String,
}

#[derive(Debug)]
pub enum Outgoing {
    Text(String),
    Close,
}

pub async fn handle_websocket(
    ws: WebSocketUpgrade,
    Extension(state): Extension<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| websocket_handler(socket, state))
}

async fn websocket_handler(socket: WebSocket, state: AppState) {
    let conn_id = Uuid::new_v4().to_string();
    let (mut ws_sender, mut ws_receiver) = socket.split();
    
    // Channel for sending messages to websocket (increased buffer for higher throughput)
    let (tx, mut rx) = mpsc::channel::<Outgoing>(1000);
    
    // Spawn task to forward messages from channel to websocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match msg {
                Outgoing::Text(s) => {
                    if ws_sender.send(Message::Text(s)).await.is_err() {
                        break;
                    }
                }
                Outgoing::Close => {
                    let _ = ws_sender.send(Message::Close(None)).await;
                    break;
                }
            }
        }
    });
    
    let mut session_id: Option<String> = None;
    let mut role: Option<String> = None;
    let mut redis_task: Option<tokio::task::JoinHandle<()>> = None;
    
    // Handle incoming websocket messages
    while let Some(msg) = ws_receiver.next().await {
        let msg = match msg {
            Ok(msg) => msg,
            Err(e) => {
                error!("WebSocket error: {}", e);
                break;
            }
        };
        
        match msg {
            Message::Text(text) => {
                if session_id.is_none() {
                    // Handle hello message
                    match serde_json::from_str::<HelloMessage>(&text) {
                        Ok(hello) if hello.msg_type == "hello" => {
                            if !["workstation", "phone"].contains(&hello.r.as_str()) {
                                break;
                            }
                            
                            match Session::load(&hello.s, &state.redis).await {
                                Ok(Some(session)) if session.token == hello.t => {
                                    session_id = Some(hello.s.clone());
                                    role = Some(hello.r.clone());
                                    
                                    // Record role in Redis
                                    let mut conn = state.redis.clone();
                                    let roles_key = format!("sess:{}:roles", hello.s);
                                    let _: () = conn.hset(&roles_key, &hello.r, &conn_id).await.unwrap_or(());

                                    // Start Redis subscriber for this session
                                    let channel = format!("ch:{}", hello.s);
                                    let channel_clone = channel.clone();
                                    let tx_clone = tx.clone();
                                    let role_clone = hello.r.clone();
                                    let sid_clone = hello.s.clone();
                                    let sid_for_pubsub = sid_clone.clone();
                                    
                                    // Start per-session Redis pubsub listener
                                    redis_task = Some(tokio::spawn(async move {
                                        if let Ok(client) = redis::Client::open(std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string())) {
                                            if let Ok(mut pubsub) = client.get_async_pubsub().await {
                                                if pubsub.subscribe(&channel_clone).await.is_ok() {
                                                    while let Some(msg) = pubsub.on_message().next().await {
                                                        let payload: String = msg.get_payload().unwrap_or_default();

                                                        // Lightweight router: check type field first to handle minimal notifications
                                                        if let Ok(val) = serde_json::from_str::<serde_json::Value>(&payload) {
                                                            if val.get("type").and_then(|v| v.as_str()) == Some("session-killed") {
                                                                if val.get("sid").and_then(|v| v.as_str()) == Some(&sid_for_pubsub) {
                                                                    let _ = tx_clone.send(Outgoing::Text(serde_json::json!({"type":"session-killed"}).to_string())).await;
                                                                    let _ = tx_clone.send(Outgoing::Close).await;
                                                                    break;
                                                                }
                                                                continue;
                                                            }
                                                        }

                                                        if let Ok(relay_msg) = serde_json::from_str::<RelayMessage>(&payload) {
                                                            // Forward messages from other role or system notifications
                                                            if relay_msg.sid == sid_for_pubsub {
                                                                if relay_msg.msg_type == "frame" && relay_msg.from_role != role_clone {
                                                                    // Forward the entire message (which the client will extract the frame from)
                                                                    if tx_clone.send(Outgoing::Text(payload.clone())).await.is_err() {
                                                                        break;
                                                                    }
                                                                } else if relay_msg.msg_type == "peer-joined" || relay_msg.msg_type == "peer-left" {
                                                                    // Send peer notifications
                                                                    let notification = serde_json::json!({
                                                                        "type": relay_msg.msg_type,
                                                                        "role": relay_msg.from_role
                                                                    });
                                                                    if tx_clone.send(Outgoing::Text(notification.to_string())).await.is_err() {
                                                                        break;
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }));

                                    // Register sender for direct kill notifications
                                    {
                                        let mut map = state.session_senders.write().await;
                                        map.entry(hello.s.clone()).or_default().push(tx.clone());
                                    }

                                    // Notify peer joined
                                    let notification = RelayMessage {
                                        msg_type: "peer-joined".to_string(),
                                        sid: hello.s.clone(),
                                        from_role: hello.r.clone(),
                                        at: chrono::Utc::now().timestamp(),
                                        frame: None,
                                        b64: None,
                                    };
                                    let _: () = conn.publish(&channel, serde_json::to_string(&notification).unwrap()).await.unwrap_or(());
                                    // Refresh session TTL on successful hello and peer notification
                                    let _ = Session::refresh(&state.redis, &hello.s, state.session_idle_secs).await;

                                    // Send hello-ack
                                    let ack = HelloAck {
                                        msg_type: "hello-ack".to_string(),
                                        session_id: hello.s.clone(),
                                    };

                                    let _ = tx.send(Outgoing::Text(serde_json::to_string(&ack).unwrap())).await;

                                    info!("Connection established: {} as {}", hello.s, hello.r);

                                    // Subscribe to in-process kill broadcast for this session
                                    let mut map = state.kill_broadcasts.write().await;
                                    let entry = map.entry(sid_clone.clone()).or_insert_with(|| {
                                        let (txb, _rxb) = broadcast::channel::<()>(8);
                                        txb
                                    });
                                    let mut kill_rx = entry.subscribe();
                                    let tx_kill = tx.clone();
                                    tokio::spawn(async move {
                                        let _ = kill_rx.recv().await;
                                        let _ = tx_kill.send(Outgoing::Text(serde_json::json!({"type":"session-killed"}).to_string())).await;
                                        let _ = tx_kill.send(Outgoing::Close).await;
                                    });
                                }
                                _ => {
                                    warn!("Invalid session or token");
                                    break;
                                }
                            }
                        }
                        _ => {
                            warn!("First message must be hello");
                            break;
                        }
                    }
                } else if let (Some(sid), Some(r)) = (&session_id, &role) {
                    // Recognize heartbeat
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                        if json.get("type").and_then(|v| v.as_str()) == Some("hb") {
                            // Refresh TTL and optionally ack
                            let _ = Session::refresh(&state.redis, sid, state.session_idle_secs).await;
                            let _ = tx.send(Outgoing::Text(serde_json::json!({"type":"hb-ack"}).to_string())).await;
                            continue;
                        }
                    }
                    // Relay the message
                    let mut conn = state.redis.clone();
                    let channel = format!("ch:{}", sid);
                    let relay_msg = RelayMessage {
                        msg_type: "frame".to_string(),
                        sid: sid.clone(),
                        from_role: r.clone(),
                        at: chrono::Utc::now().timestamp(),
                        frame: Some(text),
                        b64: Some(false),
                    };
                    let msg_str = serde_json::to_string(&relay_msg).unwrap();
                    let _: () = conn.publish(&channel, msg_str).await.unwrap_or(());
                    let _ = Session::refresh(&state.redis, sid, state.session_idle_secs).await;
                }
            }
            Message::Binary(data) => {
                if let (Some(sid), Some(r)) = (&session_id, &role) {
                    let mut conn = state.redis.clone();
                    let channel = format!("ch:{}", sid);
                    let relay_msg = RelayMessage {
                        msg_type: "frame".to_string(),
                        sid: sid.clone(),
                        from_role: r.clone(),
                        at: chrono::Utc::now().timestamp(),
                        frame: Some(base64::Engine::encode(&base64::engine::general_purpose::STANDARD, data)),
                        b64: Some(true),
                    };
                    let _: () = conn.publish(&channel, serde_json::to_string(&relay_msg).unwrap()).await.unwrap_or(());
                    let _ = Session::refresh(&state.redis, sid, state.session_idle_secs).await;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
    
    // Cleanup
    if let Some(task) = redis_task {
        task.abort();
    }
    send_task.abort();
    
    if let (Some(sid), Some(r)) = (&session_id, &role) {
        let mut conn = state.redis.clone();
        let roles_key = format!("sess:{}:roles", sid);
        let current: Option<String> = conn.hget(&roles_key, r.as_str()).await.unwrap_or(None);
        
        if current.as_ref() == Some(&conn_id) {
            let _: () = conn.hdel(&roles_key, r.as_str()).await.unwrap_or(());
            
            let channel = format!("ch:{}", sid);
            let notification = RelayMessage {
                msg_type: "peer-left".to_string(),
                sid: sid.clone(),
                from_role: r.clone(),
                at: chrono::Utc::now().timestamp(),
                frame: None,
                b64: None,
            };
            let _: () = conn.publish(&channel, serde_json::to_string(&notification).unwrap()).await.unwrap_or(());
            let _ = Session::refresh(&state.redis, sid, state.session_idle_secs).await;
        }
        
        info!("Connection closed: {} as {}", sid, r);
    }
}

// No longer need a separate redis_subscriber since each connection handles its own
