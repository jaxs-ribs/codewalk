mod session;
mod websocket;

use anyhow::Result;
use axum::{
    extract::{Extension, Json},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use dotenvy::dotenv;
use redis::aio::ConnectionManager;
use serde_json::json;
use std::{collections::HashMap, env, net::SocketAddr, sync::Arc};
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

use session::{Session, SessionStore};
use websocket::handle_websocket;

#[derive(Clone)]
pub struct AppState {
    pub redis: ConnectionManager,
    pub sessions: Arc<RwLock<SessionStore>>,
    pub connections: Arc<RwLock<HashMap<String, String>>>, // conn_id -> session_id
    pub public_ws_url: String,
    pub session_ttl: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
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
    let public_ws_url = env::var("PUBLIC_WS_URL")
        .unwrap_or_else(|_| format!("ws://localhost:{}/ws", port));
    let session_ttl: u64 = env::var("SESSION_TTL_SECS")
        .unwrap_or_else(|_| "3600".to_string())
        .parse()?;

    let client = redis::Client::open(redis_url)?;
    let redis = ConnectionManager::new(client).await?;

    let app_state = AppState {
        redis: redis.clone(),
        sessions: Arc::new(RwLock::new(SessionStore::new())),
        connections: Arc::new(RwLock::new(HashMap::new())),
        public_ws_url,
        session_ttl,
    };

    // No longer need global redis subscriber - each connection handles its own

    let app = Router::new()
        .route("/api/register", post(register_session))
        .route("/health", get(health_check))
        .route("/ws", get(handle_websocket))
        .layer(CorsLayer::permissive())
        .layer(Extension(app_state));

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server listening on {}", addr);
    info!("WebSocket endpoint: ws://{}/ws", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn register_session(Extension(state): Extension<AppState>) -> impl IntoResponse {
    let session_id = Uuid::new_v4().to_string().replace("-", "");
    let token = Uuid::new_v4().to_string().replace("-", "");
    
    let session = Session::new(session_id.clone(), token.clone());
    
    if let Err(e) = session.save(&state.redis, state.session_ttl).await {
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
        "ttl": state.session_ttl,
        "ws": state.public_ws_url,
        "qrDataUrl": format!("data:image/png;base64,{}", qr_code),
        "qrPayload": payload
    })))
}

async fn health_check() -> impl IntoResponse {
    Json(json!({ "ok": true }))
}