mod session;
mod websocket;

use anyhow::Result;
use axum::{
    extract::{Extension, Json, Query},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use dotenvy::dotenv;
use redis::{aio::ConnectionManager, AsyncCommands};
use serde_json::json;
use std::{collections::HashMap, env, net::SocketAddr, sync::Arc};
use tokio::sync::{broadcast, RwLock};
// RwLock already imported above
use tower_http::cors::CorsLayer;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

use session::{Session, SessionStore};
use websocket::handle_websocket;
use websocket::RelayMessage;
use protocol as proto;

#[derive(Clone)]
pub struct AppState {
    pub redis: ConnectionManager,
    pub sessions: Arc<RwLock<SessionStore>>,
    pub connections: Arc<RwLock<HashMap<String, String>>>, // conn_id -> session_id
    pub public_ws_url: String,
    pub session_idle_secs: u64,
    pub heartbeat_interval_secs: u64,
    pub kill_broadcasts: Arc<RwLock<HashMap<String, broadcast::Sender<()>>>>,
    pub session_senders: Arc<RwLock<HashMap<String, Vec<tokio::sync::mpsc::Sender<crate::websocket::Outgoing>>>>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Load env from top-level .env first, then local .env (if any)
    // Running from relay/server, workspace root .env is two levels up
    let _ = dotenvy::from_filename("../../.env");
    dotenv().ok();

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            env::var("RUST_LOG").unwrap_or_else(|_| "relay_server=info,tower_http=debug".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let port: u16 = env::var("PORT")
        .unwrap_or_else(|_| "3001".to_string())
        .parse()?;
    
    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    // Prefer unified RELAY_WS_URL from .env; fall back to PUBLIC_WS_URL; then default
    let public_ws_url = env::var("RELAY_WS_URL")
        .or_else(|_| env::var("PUBLIC_WS_URL"))
        .unwrap_or_else(|_| format!("ws://localhost:{}/ws", port));
    let public_ws_url_print = public_ws_url.clone();
    let session_idle_secs: u64 = env::var("SESSION_IDLE_SECS")
        .unwrap_or_else(|_| "7200".to_string())
        .parse()?;
    let heartbeat_interval_secs: u64 = env::var("HEARTBEAT_INTERVAL_SECS")
        .unwrap_or_else(|_| "30".to_string())
        .parse()?;

    let client = redis::Client::open(redis_url)?;
    let redis = ConnectionManager::new(client).await?;

    let app_state = AppState {
        redis: redis.clone(),
        sessions: Arc::new(RwLock::new(SessionStore::new())),
        connections: Arc::new(RwLock::new(HashMap::new())),
        public_ws_url,
        session_idle_secs,
        heartbeat_interval_secs,
        kill_broadcasts: Arc::new(RwLock::new(HashMap::new())),
        session_senders: Arc::new(RwLock::new(HashMap::new())),
    };

    // If a preset session is defined in .env, pre-create it
    if let (Ok(sid), Ok(tok)) = (env::var("RELAY_SESSION_ID"), env::var("RELAY_TOKEN")) {
        let session = Session::new(sid.clone(), tok.clone());
        if let Err(e) = session.save(&app_state.redis, app_state.session_idle_secs).await {
            error!("Failed to pre-create session from .env: {}", e);
        } else {
            {
                let mut sessions = app_state.sessions.write().await;
                sessions.add(session.clone());
            }
            info!("Preloaded session from .env: {}", sid);
        }
    }

    // No longer need global redis subscriber - each connection handles its own

    let app = Router::new()
        .route("/api/register", post(register_session))
        .route("/api/transcripts", post(ingest_transcript))
        .route("/api/logs", get(get_logs))
        .route("/api/session/:id", axum::routing::delete(kill_session))
        .route("/health", get(health_check))
        .route("/ws", get(handle_websocket))
        .layer(CorsLayer::permissive())
        .layer(Extension(app_state));

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server listening on {}", addr);
    info!("Public WebSocket URL: {}", public_ws_url_print);
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn register_session(Extension(state): Extension<AppState>) -> impl IntoResponse {
    let session_id = Uuid::new_v4().to_string().replace("-", "");
    let token = Uuid::new_v4().to_string().replace("-", "");
    
    let session = Session::new(session_id.clone(), token.clone());
    
    if let Err(e) = session.save(&state.redis, state.session_idle_secs).await {
        error!("Failed to save session: {}", e);
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({
            "error": "register_failed"
        })));
    }
    
    {
        let mut sessions = state.sessions.write().await;
        sessions.add(session.clone());
    }

    let payload = json!({
        "u": state.public_ws_url,
        "s": session_id,
        "t": token
    });

    let qr_code = qrcode::QrCode::new(payload.to_string())
        .map(|code| {
            let image = code.render::<image::Luma<u8>>().build();
            let mut bytes = Vec::new();
            use image::ImageEncoder;
            let encoder = image::codecs::png::PngEncoder::new(&mut bytes);
            let _ = encoder.write_image(
                image.as_raw(),
                image.width(),
                image.height(),
                image::ColorType::L8.into(),
            );
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, bytes)
        })
        .unwrap_or_default();

    (StatusCode::OK, Json(json!({
        "sessionId": session_id,
        "token": token,
        "ttl": state.session_idle_secs,
        "ws": state.public_ws_url,
        "qrDataUrl": format!("data:image/png;base64,{}", qr_code),
        "qrPayload": payload
    })))
}

async fn health_check() -> impl IntoResponse {
    Json(json!({ "ok": true }))
}

#[derive(Debug, serde::Deserialize)]
struct GetLogsQuery {
    #[serde(rename = "sid")] session_id: String,
    #[serde(rename = "tok")] token: String,
    #[serde(default)] limit: Option<usize>,
}

/// Request logs from the workstation over the relay channel and wait for a response.
async fn get_logs(
    Extension(state): Extension<AppState>,
    Query(q): Query<GetLogsQuery>,
) -> impl IntoResponse {
    // Validate session
    match Session::load(&q.session_id, &state.redis).await {
        Ok(Some(sess)) if sess.token == q.token => {}
        _ => return (StatusCode::FORBIDDEN, Json(json!({"error":"invalid_session"}))).into_response(),
    }

    let limit = q.limit.unwrap_or(100).max(1).min(200);
    let corr = Uuid::new_v4().to_string();
    let channel = format!("ch:{}", q.session_id);

    // Publish a frame as if coming from the phone role
    let frame = serde_json::json!({
        "type": "get_logs",
        "id": corr,
        "limit": limit,
    })
    .to_string();
    let relay_msg = RelayMessage {
        msg_type: "frame".to_string(),
        sid: q.session_id.clone(),
        from_role: "phone".to_string(),
        at: chrono::Utc::now().timestamp(),
        frame: Some(frame),
        b64: Some(false),
    };
    let payload = serde_json::to_string(&relay_msg).unwrap_or_else(|_| "{}".to_string());
    let mut conn = state.redis.clone();
    let _: () = conn.publish(&channel, payload).await.unwrap_or(()) ;

    // Subscribe and wait for matching logs response
    let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let client = match redis::Client::open(redis_url) { Ok(c) => c, Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error":"redis_client"}))).into_response() };
    let mut pubsub = match client.get_async_pubsub().await { Ok(p) => p, Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error":"redis_pubsub"}))).into_response() };
    if pubsub.subscribe(&channel).await.is_err() {
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error":"subscribe_failed"}))).into_response();
    }

    use futures::StreamExt;
    use tokio::time::{timeout, Duration};
    let deadline = Duration::from_secs(5);
    while let Ok(Some(msg)) = timeout(deadline, pubsub.on_message().next()).await {
        let payload: String = msg.get_payload().unwrap_or_default();
        if let Ok(relay) = serde_json::from_str::<RelayMessage>(&payload) {
            if relay.msg_type == "frame" && relay.frame.is_some() && relay.from_role == "workstation" {
                if let Some(inner) = relay.frame {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&inner) {
                        if v.get("type").and_then(|s| s.as_str()) == Some("logs") && v.get("replyTo").and_then(|s| s.as_str()) == Some(corr.as_str()) {
                            let items = v.get("items").cloned().unwrap_or_else(|| serde_json::json!([]));
                            // Best-effort TTL refresh
                            let _ = Session::refresh(&state.redis, &q.session_id, state.session_idle_secs).await;
                            return (StatusCode::OK, Json(json!({"items": items}))).into_response();
                        }
                    }
                }
            }
        }
    }
    (StatusCode::GATEWAY_TIMEOUT, Json(json!({"error":"timeout"}))).into_response()
}

#[derive(Debug, serde::Deserialize)]
struct IngestTranscriptReq {
    #[serde(rename = "sid")] pub session_id: String,
    #[serde(rename = "tok")] pub token: String,
    pub text: String,
    #[serde(default)] pub final_: bool,
    #[serde(default)] pub source: Option<String>,
    #[serde(default)] pub id: Option<String>,
}

/// Minimal HTTP ingest for transcripts; publishes a protocol::user_text frame to the session channel.
async fn ingest_transcript(
    Extension(state): Extension<AppState>,
    Json(req): Json<IngestTranscriptReq>,
) -> impl IntoResponse {
    // Validate session/token
    match Session::load(&req.session_id, &state.redis).await {
        Ok(Some(sess)) if sess.token == req.token => {
            let inner = proto::Message::UserText(proto::UserText {
                v: Some(proto::VERSION),
                id: req.id.clone(),
                text: req.text,
                source: Some(req.source.unwrap_or_else(|| "api".to_string())),
                final_: req.final_,
            });
            // Relay as a frame from the "phone" role to reach workstation
            let relay_msg = RelayMessage {
                msg_type: "frame".to_string(),
                sid: req.session_id.clone(),
                from_role: "phone".to_string(),
                at: chrono::Utc::now().timestamp(),
                frame: Some(serde_json::to_string(&inner).unwrap_or_else(|_| "{}".to_string())),
                b64: Some(false),
            };
            let payload = serde_json::to_string(&relay_msg).unwrap_or_default();
            let channel = format!("ch:{}", req.session_id);
            let mut conn = state.redis.clone();
            let _: () = conn.publish(&channel, payload).await.unwrap_or(());
            // Refresh TTL
            let _ = Session::refresh(&state.redis, &req.session_id, state.session_idle_secs).await;
            (StatusCode::ACCEPTED, Json(json!({"ok": true})))
        }
        _ => (StatusCode::FORBIDDEN, Json(json!({"error": "invalid_session"}))),
    }
}

async fn kill_session(
    axum::extract::Path(id): axum::extract::Path<String>,
    Extension(state): Extension<AppState>,
) -> impl IntoResponse {
    let mut conn = state.redis.clone();
    let sess_key = format!("sess:{}", id);
    let roles_key = format!("sess:{}:roles", id);
    let channel_key = format!("ch:{}", id);

    // Check if exists
    match conn.exists(&sess_key).await {
        Ok(true) => {
            let _: () = conn.del(&sess_key).await.unwrap_or(());
            let _: () = conn.del(&roles_key).await.unwrap_or(());
            // Publish session-killed notification via Redis
            let msg = serde_json::json!({
                "type": "session-killed",
                "sid": id,
            })
            .to_string();
            let _: () = conn.publish(&channel_key, msg).await.unwrap_or(());

            // Also notify in-process subscribers (reliable control path)
            if let Some(tx) = {
                let map = state.kill_broadcasts.read().await;
                map.get(&id).cloned()
            } {
                let _ = tx.send(());
            }

            // Best-effort: notify any active websocket senders directly
            if let Some(list) = {
                let map = state.session_senders.read().await;
                map.get(&id).cloned()
            } {
                for sender in list {
                    let _ = sender.send(crate::websocket::Outgoing::Text(serde_json::json!({"type":"session-killed"}).to_string())).await;
                    let _ = sender.send(crate::websocket::Outgoing::Close).await;
                }
            }
            (StatusCode::NO_CONTENT, ())
        }
        Ok(false) | Err(_) => (StatusCode::NOT_FOUND, ()),
    }
}
