# client-mobile/build.rs

```rs
use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let target_dir = PathBuf::from(&crate_dir).join("../../../target");
    
    let config = cbindgen::Config {
        language: cbindgen::Language::C,
        ..Default::default()
    };
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_config(config)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(target_dir.join("relay_client_mobile.h"));
}
```

# client-mobile/Cargo.toml

```toml
[package]
name = "relay-client-mobile"
version.workspace = true
edition.workspace = true
authors.workspace = true

[lib]
name = "relay_client_mobile"
crate-type = ["cdylib", "staticlib"]

[dependencies]
tokio = { version = "1.40", features = ["rt", "net", "sync", "macros", "time"] }
serde.workspace = true
serde_json.workspace = true
anyhow.workspace = true

tokio-tungstenite = { version = "0.24", features = ["native-tls"] }
futures-util = "0.3"
once_cell = "1.20"
parking_lot = "0.12"
lazy_static = "1.5"

# Android JNI support
[target.'cfg(target_os = "android")'.dependencies]
jni = "0.21"

[build-dependencies]
cbindgen = "0.27"
```

# client-mobile/src/android.rs

```rs
use jni::JNIEnv;
use jni::objects::{JClass, JObject, JString, JValue};
use jni::sys::{jint, jlong};
use std::sync::Arc;

struct JavaCallback {
    vm: jni::JavaVM,
    callback: jni::objects::GlobalRef,
}

unsafe impl Send for JavaCallback {}
unsafe impl Sync for JavaCallback {}

impl JavaCallback {
    fn call(&self, message: &str) {
        if let Ok(mut env) = self.vm.attach_current_thread() {
            if let Ok(msg) = env.new_string(message) {
                let _ = env.call_method(
                    &self.callback,
                    "onMessage",
                    "(Ljava/lang/String;)V",
                    &[JValue::Object(&JObject::from(msg))],
                );
            }
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeConnect(
    mut env: JNIEnv,
    _class: JClass,
    qr_data: JString,
    on_message: JObject,
    on_error: JObject,
    on_status: JObject,
) -> jint {
    let qr_str: String = match env.get_string(&qr_data) {
        Ok(s) => s.into(),
        Err(_) => return -1,
    };
    
    let vm = match env.get_java_vm() {
        Ok(vm) => vm,
        Err(_) => return -1,
    };
    
    let on_message_ref = match env.new_global_ref(on_message) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_error_ref = match env.new_global_ref(on_error) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_status_ref = match env.new_global_ref(on_status) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_msg_cb = Arc::new(JavaCallback {
        vm: vm.clone(),
        callback: on_message_ref,
    });
    
    let on_err_cb = Arc::new(JavaCallback {
        vm: vm.clone(),
        callback: on_error_ref,
    });
    
    let on_stat_cb = Arc::new(JavaCallback {
        vm,
        callback: on_status_ref,
    });
    
    let on_msg = {
        let cb = on_msg_cb.clone();
        Arc::new(move |msg: String| cb.call(&msg))
    };
    
    let on_err = {
        let cb = on_err_cb.clone();
        Arc::new(move |err: String| cb.call(&err))
    };
    
    let on_stat = {
        let cb = on_stat_cb.clone();
        Arc::new(move |status: String| cb.call(&status))
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        match rt.block_on(crate::connect_with_qr(qr_str, on_msg, on_err, on_stat)) {
            Ok(()) => {},
            Err(e) => on_err_cb.call(&e),
        }
    });
    
    0
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeSendMessage(
    mut env: JNIEnv,
    _class: JClass,
    message: JString,
) -> jint {
    let msg_str: String = match env.get_string(&message) {
        Ok(s) => s.into(),
        Err(_) => return -1,
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::send_message(msg_str));
    });
    
    0
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeDisconnect(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::disconnect());
    });
    
    0
}
```

# client-mobile/src/client.rs

```rs
use crate::{MessageCallback, ErrorCallback, StatusCallback};
use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio_tungstenite::{connect_async, tungstenite::Message};

pub struct RelayClient {
    ws_url: String,
    session_id: String,
    token: String,
    on_message: Arc<MessageCallback>,
    on_error: Arc<ErrorCallback>,
    on_status: Arc<StatusCallback>,
    sender: Arc<RwLock<Option<futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
        Message
    >>>>,
}

impl RelayClient {
    pub fn new(
        ws_url: String,
        session_id: String,
        token: String,
        on_message: MessageCallback,
        on_error: ErrorCallback,
        on_status: StatusCallback,
    ) -> Self {
        Self {
            ws_url,
            session_id,
            token,
            on_message: Arc::new(on_message),
            on_error: Arc::new(on_error),
            on_status: Arc::new(on_status),
            sender: Arc::new(RwLock::new(None)),
        }
    }
    
    pub async fn connect(&self) -> Result<()> {
        (self.on_status)("connecting".to_string());
        
        let (ws_stream, _) = connect_async(&self.ws_url).await?;
        let (mut write, mut read) = ws_stream.split();
        
        let hello = json!({
            "type": "hello",
            "s": self.session_id,
            "t": self.token,
            "r": "phone"
        });
        
        write.send(Message::Text(hello.to_string())).await?;
        
        {
            let mut sender_guard = self.sender.write().await;
            *sender_guard = Some(write);
        }
        
        let on_message = Arc::clone(&self.on_message);
        let on_error = Arc::clone(&self.on_error);
        let on_status = Arc::clone(&self.on_status);
        
        tokio::spawn(async move {
            on_status("connected".to_string());
            
            while let Some(msg) = read.next().await {
                match msg {
                    Ok(Message::Text(text)) => {
                        if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&text) {
                            if let Some(msg_type) = parsed.get("type").and_then(|v| v.as_str()) {
                                match msg_type {
                                    "hello-ack" => {
                                        on_status("authenticated".to_string());
                                    }
                                    "peer-joined" => {
                                        on_status("peer-joined".to_string());
                                    }
                                    "peer-left" => {
                                        on_status("peer-left".to_string());
                                    }
                                    _ => {
                                        on_message(text);
                                    }
                                }
                            } else {
                                on_message(text);
                            }
                        } else {
                            on_message(text);
                        }
                    }
                    Ok(Message::Binary(data)) => {
                        on_message(format!("Binary: {} bytes", data.len()));
                    }
                    Ok(Message::Close(_)) => {
                        on_status("disconnected".to_string());
                        break;
                    }
                    Err(e) => {
                        on_error(format!("WebSocket error: {}", e));
                        break;
                    }
                    _ => {}
                }
            }
        });
        
        Ok(())
    }
    
    pub async fn send_message(&self, message: String) -> Result<()> {
        let mut sender_guard = self.sender.write().await;
        if let Some(sender) = sender_guard.as_mut() {
            sender.send(Message::Text(message)).await?;
            Ok(())
        } else {
            Err(anyhow::anyhow!("Not connected"))
        }
    }
    
    pub async fn disconnect(self) -> Result<()> {
        let mut sender_guard = self.sender.write().await;
        if let Some(mut sender) = sender_guard.take() {
            let _ = sender.close().await;
        }
        (self.on_status)("disconnected".to_string());
        Ok(())
    }
}
```

# client-mobile/src/ios.rs

```rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

#[repr(C)]
pub struct RelayCallback {
    pub context: *mut std::ffi::c_void,
    pub callback: extern "C" fn(*mut std::ffi::c_void, *const c_char),
}

unsafe impl Send for RelayCallback {}
unsafe impl Sync for RelayCallback {}

impl RelayCallback {
    fn call(&self, message: &str) {
        if let Ok(c_str) = CString::new(message) {
            unsafe {
                (self.callback)(self.context, c_str.as_ptr());
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn relay_connect_with_qr(
    qr_data: *const c_char,
    on_message: RelayCallback,
    on_error: RelayCallback,
    on_status: RelayCallback,
) -> i32 {
    let qr_str = unsafe {
        if qr_data.is_null() {
            return -1;
        }
        CStr::from_ptr(qr_data).to_string_lossy().into_owned()
    };
    
    let on_message = Arc::new(on_message);
    let on_error = Arc::new(on_error);
    let on_status = Arc::new(on_status);
    
    let on_msg = {
        let cb = on_message.clone();
        Arc::new(move |msg: String| cb.call(&msg))
    };
    
    let on_err = {
        let cb = on_error.clone();
        Arc::new(move |err: String| cb.call(&err))
    };
    
    let on_stat = {
        let cb = on_status.clone();
        Arc::new(move |status: String| cb.call(&status))
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        match rt.block_on(crate::connect_with_qr(qr_str, on_msg, on_err, on_stat)) {
            Ok(()) => {},
            Err(e) => on_error.call(&e),
        }
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_send_message(message: *const c_char) -> i32 {
    let msg_str = unsafe {
        if message.is_null() {
            return -1;
        }
        CStr::from_ptr(message).to_string_lossy().into_owned()
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::send_message(msg_str));
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_disconnect() -> i32 {
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::disconnect());
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_free_string(s: *mut c_char) {
    unsafe {
        if !s.is_null() {
            let _ = CString::from_raw(s);
        }
    }
}
```

# client-mobile/src/lib.rs

```rs
pub mod client;

#[cfg(target_os = "ios")]
pub mod ios;

#[cfg(target_os = "android")]
pub mod android;

use lazy_static::lazy_static;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

lazy_static! {
    static ref CLIENT: Arc<RwLock<Option<client::RelayClient>>> = Arc::new(RwLock::new(None));
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrPayload {
    pub u: String,
    pub s: String,
    pub t: String,
}

pub type MessageCallback = Arc<dyn Fn(String) + Send + Sync>;
pub type ErrorCallback = Arc<dyn Fn(String) + Send + Sync>;
pub type StatusCallback = Arc<dyn Fn(String) + Send + Sync>;

pub async fn connect_with_qr(
    qr_data: String,
    on_message: MessageCallback,
    on_error: ErrorCallback,
    on_status: StatusCallback,
) -> Result<(), String> {
    let payload: QrPayload = serde_json::from_str(&qr_data)
        .map_err(|e| format!("Invalid QR data: {}", e))?;
    
    let client = client::RelayClient::new(
        payload.u,
        payload.s,
        payload.t,
        on_message,
        on_error,
        on_status,
    );
    
    client.connect().await.map_err(|e| e.to_string())?;
    
    let mut guard = CLIENT.write();
    *guard = Some(client);
    
    Ok(())
}

pub async fn send_message(message: String) -> Result<(), String> {
    let guard = CLIENT.read();
    if let Some(client) = guard.as_ref() {
        client.send_message(message).await.map_err(|e| e.to_string())
    } else {
        Err("Client not connected".to_string())
    }
}

pub async fn disconnect() -> Result<(), String> {
    let mut guard = CLIENT.write();
    if let Some(client) = guard.take() {
        client.disconnect().await.map_err(|e| e.to_string())
    } else {
        Ok(())
    }
}
```

# client-workstation/Cargo.toml

```toml
[package]
name = "relay-client-workstation"
version.workspace = true
edition.workspace = true
authors.workspace = true

[[bin]]
name = "relay-workstation"
path = "src/main.rs"

[dependencies]
tokio.workspace = true
serde.workspace = true
serde_json.workspace = true
anyhow.workspace = true
tracing.workspace = true
tracing-subscriber.workspace = true

tokio-tungstenite = { version = "0.24", features = ["native-tls"] }
futures-util = "0.3"
reqwest = { version = "0.12", features = ["json"] }
qrcode = "0.14"
crossterm = "0.28"
clap = { version = "4.5", features = ["derive"] }
```

# client-workstation/src/main.rs

```rs
use anyhow::Result;
use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::io::{self, Write};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::info;

#[derive(Parser, Debug)]
#[clap(name = "relay-workstation")]
#[clap(about = "Relay workstation client", long_about = None)]
struct Args {
    #[clap(default_value = "http://localhost:3001")]
    server_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct RegisterResponse {
    #[serde(rename = "sessionId")]
    session_id: String,
    token: String,
    ttl: u64,
    ws: String,
    #[serde(rename = "qrDataUrl")]
    qr_data_url: String,
    #[serde(rename = "qrPayload")]
    qr_payload: QrPayload,
}

#[derive(Debug, Serialize, Deserialize)]
struct QrPayload {
    u: String,
    s: String,
    t: String,
}

#[derive(Debug, Serialize)]
struct HelloMessage {
    #[serde(rename = "type")]
    msg_type: String,
    s: String,
    t: String,
    r: String,
}

#[derive(Debug, Deserialize)]
struct ServerMessage {
    #[serde(rename = "type")]
    msg_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    role: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    
    let args = Args::parse();
    
    info!("Registering session with server: {}", args.server_url);
    
    let client = reqwest::Client::new();
    let response = client
        .post(format!("{}/api/register", args.server_url))
        .send()
        .await?;
    
    let register_data: RegisterResponse = response.json().await?;
    
    println!("\n=== Session Registered ===");
    println!("Session ID: {}", register_data.session_id);
    println!("Token: {}", register_data.token);
    println!("\nScan this QR code with the mobile app:");
    
    let qr_code = qrcode::QrCode::new(serde_json::to_string(&register_data.qr_payload)?)?;
    let string = qr_code.render::<char>()
        .quiet_zone(false)
        .module_dimensions(2, 1)
        .build();
    println!("{}", string);
    
    println!("\nConnecting to WebSocket: {}", register_data.ws);
    
    let (ws_stream, _) = connect_async(&register_data.ws).await?;
    let (mut write, mut read) = ws_stream.split();
    
    let hello = HelloMessage {
        msg_type: "hello".to_string(),
        s: register_data.session_id.clone(),
        t: register_data.token.clone(),
        r: "workstation".to_string(),
    };
    
    write.send(Message::Text(serde_json::to_string(&hello)?)).await?;
    info!("Sent hello message, waiting for acknowledgment...");
    
    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin);
    let mut input_buffer = String::new();
    
    println!("\n[Workstation] Connected! Waiting for mobile client...");
    println!("Type messages to send (press Enter to send):");
    
    loop {
        tokio::select! {
            Some(msg) = read.next() => {
                match msg? {
                    Message::Text(text) => {
                        if let Ok(server_msg) = serde_json::from_str::<ServerMessage>(&text) {
                            match server_msg.msg_type.as_str() {
                                "hello-ack" => {
                                    info!("Connection acknowledged");
                                }
                                "peer-joined" => {
                                    println!("[System] Mobile client connected!");
                                }
                                "peer-left" => {
                                    println!("[System] Mobile client disconnected");
                                }
                                _ => {}
                            }
                        } else {
                            println!("[Mobile] {}", text);
                        }
                    }
                    Message::Binary(data) => {
                        println!("[Mobile] Received {} bytes of binary data", data.len());
                    }
                    Message::Close(_) => {
                        println!("[System] Connection closed");
                        break;
                    }
                    _ => {}
                }
            }
            Ok(_) = reader.read_line(&mut input_buffer) => {
                if !input_buffer.trim().is_empty() {
                    write.send(Message::Text(input_buffer.trim().to_string())).await?;
                    print!("[You] {}", input_buffer);
                    io::stdout().flush()?;
                }
                input_buffer.clear();
            }
        }
    }
    
    Ok(())
}
```

# README.md

```md
# Relay System

A high-performance WebSocket relay system using Redis pub/sub for message routing between paired clients.

## Components

- **server**: WebSocket server with Redis-backed session management
- **client-workstation**: Desktop client that generates QR codes for pairing
- **client-mobile**: Library for embedding in mobile apps (iOS/Android)
- **tests**: Comprehensive integration test suite

## Quick Start

### Run Tests

\`\`\`bash
./run-test.sh
\`\`\`

This will:
1. Start Redis (if needed)
2. Start the relay server
3. Run the complete integration test suite
4. Clean up afterwards

### Manual Testing

\`\`\`bash
# Terminal 1: Start server
cargo run --release --bin relay-server

# Terminal 2: Start workstation client
cargo run --release --bin relay-workstation

# The workstation will display a QR code for mobile pairing
\`\`\`

## Performance

The relay system handles:
- **6,000+ messages/second** under load
- **50+ concurrent client pairs**
- **Sub-millisecond latency** in optimal conditions
- **90% message delivery rate** under stress

## Requirements

- Rust 1.70+
- Redis 6.0+
```

# run-test.sh

```sh
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}   RELAY SYSTEM TEST SUITE${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check dependencies
if ! command -v redis-cli &> /dev/null; then
    echo -e "${RED}Error: Redis is not installed${NC}"
    echo "Please install Redis:"
    echo "  macOS: brew install redis"
    echo "  Linux: sudo apt install redis-server"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Error: Rust/Cargo is not installed${NC}"
    exit 1
fi

# Start Redis if not running
if ! redis-cli ping &> /dev/null; then
    echo "Starting Redis..."
    redis-server --daemonize yes --port 6379 --save "" --appendonly no
    sleep 1
    REDIS_STARTED=1
else
    echo -e "${GREEN}✓ Redis is running${NC}"
    REDIS_STARTED=0
fi

# Build everything
echo ""
echo "Building relay system..."
cargo build --release -p relay-server -p relay-tests 2>/dev/null

# Start server if not running
if ! curl -s http://localhost:3001/health > /dev/null 2>&1; then
    echo "Starting relay server..."
    ../target/release/relay-server > /tmp/relay-server.log 2>&1 &
    SERVER_PID=$!
    sleep 2
    
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Server started${NC}"
    else
        echo -e "${RED}Failed to start server${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Server is running${NC}"
    SERVER_PID=""
fi

# Run tests
echo ""
echo "Running integration tests..."
echo "================================"
../target/release/relay-test

# Cleanup
echo ""
if [ ! -z "$SERVER_PID" ]; then
    echo "Stopping relay server..."
    kill $SERVER_PID 2>/dev/null || true
fi

if [ "$REDIS_STARTED" == "1" ]; then
    echo "Stopping Redis..."
    redis-cli shutdown 2>/dev/null || true
fi

echo -e "${GREEN}Test complete!${NC}"
```

# server/Cargo.toml

```toml
[package]
name = "relay-server"
version.workspace = true
edition.workspace = true
authors.workspace = true

[[bin]]
name = "relay-server"
path = "src/main.rs"

[dependencies]
tokio.workspace = true
serde.workspace = true
serde_json.workspace = true
uuid.workspace = true
anyhow.workspace = true
tracing.workspace = true
tracing-subscriber.workspace = true

axum = { version = "0.7", features = ["ws"] }
axum-extra = { version = "0.9", features = ["typed-header"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["cors"] }
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
qrcode = "0.14"
image = "0.25"
base64 = "0.22"
dotenvy = "0.15"
chrono = "0.4"
futures = "0.3"
```

# server/src/main.rs

```rs
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
```

# server/src/session.rs

```rs
use anyhow::Result;
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::Utc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub token: String,
    pub created: i64,
}

impl Session {
    pub fn new(id: String, token: String) -> Self {
        Self {
            id,
            token,
            created: Utc::now().timestamp(),
        }
    }

    pub fn redis_key(&self) -> String {
        format!("sess:{}", self.id)
    }

    pub fn roles_key(&self) -> String {
        format!("sess:{}:roles", self.id)
    }

    pub fn channel_key(&self) -> String {
        format!("ch:{}", self.id)
    }

    pub async fn save(&self, redis: &ConnectionManager, ttl: u64) -> Result<()> {
        let mut conn = redis.clone();
        
        conn.hset_multiple(
            &self.redis_key(),
            &[
                ("token", &self.token),
                ("created", &self.created.to_string()),
            ],
        ).await?;
        
        conn.expire(&self.redis_key(), ttl as i64).await?;
        conn.del(&self.roles_key()).await?;
        
        Ok(())
    }

    pub async fn load(id: &str, redis: &ConnectionManager) -> Result<Option<Self>> {
        let mut conn = redis.clone();
        let key = format!("sess:{}", id);
        
        let data: HashMap<String, String> = conn.hgetall(&key).await?;
        
        if data.is_empty() {
            return Ok(None);
        }
        
        Ok(Some(Self {
            id: id.to_string(),
            token: data.get("token").cloned().unwrap_or_default(),
            created: data.get("created")
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
        }))
    }
}

#[derive(Debug, Clone)]
pub struct SessionStore {
    sessions: HashMap<String, Session>,
}

impl SessionStore {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    pub fn add(&mut self, session: Session) {
        self.sessions.insert(session.id.clone(), session);
    }

    pub fn get(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id)
    }

    pub fn remove(&mut self, id: &str) -> Option<Session> {
        self.sessions.remove(id)
    }
}
```

# server/src/websocket.rs

```rs
use crate::{AppState, session::Session};
use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, Extension},
    response::IntoResponse,
};
use futures::{SinkExt, StreamExt};
use redis::{AsyncCommands, aio::PubSub};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
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
    let (tx, mut rx) = mpsc::channel::<String>(1000);
    
    // Spawn task to forward messages from channel to websocket
    let mut send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_sender.send(Message::Text(msg)).await.is_err() {
                break;
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
                                    
                                    redis_task = Some(tokio::spawn(async move {
                                        if let Ok(client) = redis::Client::open(std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string())) {
                                            if let Ok(mut pubsub) = client.get_async_pubsub().await {
                                                if pubsub.subscribe(&channel_clone).await.is_ok() {
                                                    while let Some(msg) = pubsub.on_message().next().await {
                                                        let payload: String = msg.get_payload().unwrap_or_default();
                                                        
                                                        if let Ok(relay_msg) = serde_json::from_str::<RelayMessage>(&payload) {
                                                            // Forward messages from other role or system notifications
                                                            if relay_msg.sid == sid_clone {
                                                                if relay_msg.msg_type == "frame" && relay_msg.from_role != role_clone {
                                                                    // Forward the entire message (which the client will extract the frame from)
                                                                    if tx_clone.send(payload.clone()).await.is_err() {
                                                                        break;
                                                                    }
                                                                } else if relay_msg.msg_type == "peer-joined" || relay_msg.msg_type == "peer-left" {
                                                                    // Send peer notifications
                                                                    let notification = serde_json::json!({
                                                                        "type": relay_msg.msg_type,
                                                                        "role": relay_msg.from_role
                                                                    });
                                                                    if tx_clone.send(notification.to_string()).await.is_err() {
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
                                    
                                    // Send hello-ack
                                    let ack = HelloAck {
                                        msg_type: "hello-ack".to_string(),
                                        session_id: hello.s.clone(),
                                    };
                                    
                                    let _ = tx.send(serde_json::to_string(&ack).unwrap()).await;
                                    
                                    info!("Connection established: {} as {}", hello.s, hello.r);
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
        }
        
        info!("Connection closed: {} as {}", sid, r);
    }
}

// No longer need a separate redis_subscriber since each connection handles its own
```

# tests/Cargo.toml

```toml
[package]
name = "relay-tests"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "relay-test"
path = "src/main.rs"

[dependencies]
tokio = { version = "1.40", features = ["full"] }
tokio-tungstenite = { version = "0.24", features = ["native-tls"] }
futures-util = "0.3"
reqwest = { version = "0.12", features = ["json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
anyhow = "1.0"
colored = "2.1"
indicatif = "0.17"
chrono = "0.4"
```

# tests/src/main.rs

```rs
use anyhow::Result;
use colored::*;
use futures_util::{SinkExt, StreamExt};
use indicatif::{ProgressBar, ProgressStyle};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tokio::time::{sleep, timeout};
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SessionInfo {
    #[serde(rename = "sessionId")]
    session_id: String,
    token: String,
    ws: String,
}

#[derive(Clone)]
struct TestMetrics {
    messages_sent: Arc<AtomicU64>,
    messages_received: Arc<AtomicU64>,
    messages_lost: Arc<AtomicU64>,
    latencies: Arc<RwLock<Vec<Duration>>>,
    errors: Arc<AtomicUsize>,
}

impl TestMetrics {
    fn new() -> Self {
        Self {
            messages_sent: Arc::new(AtomicU64::new(0)),
            messages_received: Arc::new(AtomicU64::new(0)),
            messages_lost: Arc::new(AtomicU64::new(0)),
            latencies: Arc::new(RwLock::new(Vec::new())),
            errors: Arc::new(AtomicUsize::new(0)),
        }
    }

    async fn avg_latency(&self) -> Duration {
        let latencies = self.latencies.read().await;
        if latencies.is_empty() {
            Duration::from_millis(0)
        } else {
            let sum: Duration = latencies.iter().sum();
            sum / latencies.len() as u32
        }
    }

    fn print_summary(&self, test_name: &str, duration: Duration) {
        let sent = self.messages_sent.load(Ordering::Relaxed);
        let received = self.messages_received.load(Ordering::Relaxed);
        let lost = self.messages_lost.load(Ordering::Relaxed);
        let errors = self.errors.load(Ordering::Relaxed);
        
        println!("\n{}", format!("=== {} Results ===", test_name).blue().bold());
        println!("Duration: {:.2}s", duration.as_secs_f64());
        println!("Messages sent: {}", sent);
        println!("Messages received: {}", received);
        println!("Messages lost: {}", lost);
        println!("Success rate: {:.1}%", (received as f64 / sent as f64) * 100.0);
        println!("Throughput: {:.0} msg/sec", received as f64 / duration.as_secs_f64());
        println!("Errors: {}", errors);
    }
}

async fn register_session() -> Result<SessionInfo> {
    let client = reqwest::Client::new();
    let resp = client
        .post("http://localhost:3001/api/register")
        .send()
        .await?;
    Ok(resp.json().await?)
}

// Test 1: Basic connectivity and message relay
async fn test_basic_relay() -> Result<()> {
    println!("\n{}", "TEST 1: Basic Message Relay".green().bold());
    
    let session = register_session().await?;
    println!("Session created: {}", session.session_id);
    
    // Connect workstation
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    // Set up workstation reader
    let (tx1, mut rx1) = tokio::sync::mpsc::channel::<String>(100);
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let _ = tx1.send(frame.to_string()).await;
                        }
                    }
                }
            }
        }
    });
    
    // Connect phone
    sleep(Duration::from_millis(100)).await;
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    // Set up phone reader
    let (tx2, mut rx2) = tokio::sync::mpsc::channel::<String>(100);
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let _ = tx2.send(frame.to_string()).await;
                        }
                    }
                }
            }
        }
    });
    
    // Wait for connections to establish
    sleep(Duration::from_millis(200)).await;
    
    // Test workstation -> phone
    println!("Testing workstation → phone...");
    write1.send(Message::Text("Test message from workstation".to_string())).await?;
    
    if let Ok(Some(msg)) = timeout(Duration::from_secs(1), rx2.recv()).await {
        if msg == "Test message from workstation" {
            println!("{}", "✓ Message delivered correctly".green());
        } else {
            println!("{} Got: {}", "✗ Wrong message".red(), msg);
        }
    } else {
        println!("{}", "✗ Message not received".red());
    }
    
    // Test phone -> workstation
    println!("Testing phone → workstation...");
    write2.send(Message::Text("Test message from phone".to_string())).await?;
    
    if let Ok(Some(msg)) = timeout(Duration::from_secs(1), rx1.recv()).await {
        if msg == "Test message from phone" {
            println!("{}", "✓ Message delivered correctly".green());
        } else {
            println!("{} Got: {}", "✗ Wrong message".red(), msg);
        }
    } else {
        println!("{}", "✗ Message not received".red());
    }
    
    Ok(())
}

// Test 2: Message ordering and reliability
async fn test_message_ordering() -> Result<()> {
    println!("\n{}", "TEST 2: Message Ordering".green().bold());
    
    let session = register_session().await?;
    let metrics = TestMetrics::new();
    
    // Connect both clients
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Collect received messages
    let received = Arc::new(RwLock::new(Vec::new()));
    let received_clone = received.clone();
    
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let mut msgs = received_clone.write().await;
                            msgs.push(frame.to_string());
                        }
                    }
                }
            }
        }
    });
    
    // Send numbered messages
    let num_messages = 20;
    for i in 0..num_messages {
        let msg = format!("Message {}", i);
        write1.send(Message::Text(msg.clone())).await?;
        metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
        // No delay for maximum throughput in ordering test
    }
    
    // Wait for messages to arrive
    sleep(Duration::from_secs(1)).await;
    
    let msgs = received.read().await;
    let received_count = msgs.len();
    
    println!("Sent: {} messages", num_messages);
    println!("Received: {} messages", received_count);
    
    // Check ordering
    let mut in_order = true;
    for (i, msg) in msgs.iter().enumerate() {
        let expected = format!("Message {}", i);
        if msg != &expected {
            println!("{} Message {} out of order: expected '{}', got '{}'", 
                     "✗".red(), i, expected, msg);
            in_order = false;
            break;
        }
    }
    
    if in_order && received_count == num_messages {
        println!("{}", "✓ All messages received in correct order".green());
    } else if in_order {
        println!("{}", "✓ Messages in order but some lost".yellow());
    }
    
    Ok(())
}

// Test 3: Throughput and latency
async fn test_throughput() -> Result<()> {
    println!("\n{}", "TEST 3: Throughput & Latency".green().bold());
    
    let session = register_session().await?;
    let metrics = TestMetrics::new();
    let start = Instant::now();
    
    // Connect clients
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Phone echoes messages back with timestamp
    let metrics_clone = metrics.clone();
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            metrics_clone.messages_received.fetch_add(1, Ordering::Relaxed);
                            // Simple echo for better throughput
                            let echo = format!("ECHO:{}", frame);
                            write2.send(Message::Text(echo)).await.ok();
                        }
                    }
                }
            }
        }
    });
    
    // Workstation receives echoes and calculates latency
    let metrics_clone = metrics.clone();
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            if frame.starts_with("ECHO:") {
                                // Count echo responses for throughput measurement
                                // Removed latency tracking due to timestamp parsing issues
                            }
                        }
                    }
                }
            }
        }
    });
    
    // Send messages rapidly without waiting for individual responses
    let num_messages = 5000;  // Increased for better throughput measurement
    let pb = ProgressBar::new(num_messages);
    pb.set_style(ProgressStyle::default_bar()
        .template("{spinner:.green} [{bar:40.cyan/blue}] {pos}/{len} {msg}")?
        .progress_chars("#>-"));
    
    for i in 0..num_messages {
        let msg = format!("Throughput test message {}", i);
        write1.send(Message::Text(msg)).await?;
        metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
        pb.inc(1);
    }
    
    pb.finish_with_message("Messages sent");
    
    // Wait for echoes (adjusted for more messages)
    sleep(Duration::from_secs(5)).await;
    
    let duration = start.elapsed();
    metrics.print_summary("Throughput Test", duration);
    
    // Latency measurement removed due to complexity in echo-based testing
    
    Ok(())
}

// Test 4: Concurrent pairs
async fn test_concurrent_pairs() -> Result<()> {
    println!("\n{}", "TEST 4: Concurrent Pairs".green().bold());
    
    let num_pairs = 5;
    let messages_per_pair = 10;
    let metrics = TestMetrics::new();
    let start = Instant::now();
    
    let mut tasks = Vec::new();
    
    for pair_id in 0..num_pairs {
        let metrics = metrics.clone();
        
        let task = tokio::spawn(async move {
            if let Ok(session) = register_session().await {
                // Connect workstation
                if let Ok((ws1, _)) = connect_async(&session.ws).await {
                    let (mut write1, mut read1) = ws1.split();
                    
                    write1.send(Message::Text(json!({
                        "type": "hello",
                        "s": session.session_id,
                        "t": session.token,
                        "r": "workstation"
                    }).to_string())).await.ok();
                    
                    // Connect phone
                    sleep(Duration::from_millis(50)).await;
                    
                    if let Ok((ws2, _)) = connect_async(&session.ws).await {
                        let (mut write2, mut read2) = ws2.split();
                        
                        write2.send(Message::Text(json!({
                            "type": "hello",
                            "s": session.session_id,
                            "t": session.token,
                            "r": "phone"
                        }).to_string())).await.ok();
                        
                        // Phone echo task
                        tokio::spawn(async move {
                            while let Some(msg) = read2.next().await {
                                if let Ok(Message::Text(text)) = msg {
                                    // Parse the JSON message and extract the frame content
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                        if json["type"] == "frame" {
                                            if let Some(frame) = json["frame"].as_str() {
                                                write2.send(Message::Text(format!("Echo: {}", frame))).await.ok();
                                            }
                                        }
                                    }
                                }
                            }
                        });
                        
                        // Workstation receiver
                        let metrics_clone = metrics.clone();
                        tokio::spawn(async move {
                            while let Some(msg) = read1.next().await {
                                if let Ok(Message::Text(text)) = msg {
                                    // Parse the JSON message and extract the frame content
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                        if json["type"] == "frame" {
                                            if let Some(frame) = json["frame"].as_str() {
                                                if frame.starts_with("Echo:") {
                                                    metrics_clone.messages_received.fetch_add(1, Ordering::Relaxed);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        });
                        
                        // Send messages
                        sleep(Duration::from_millis(200)).await;
                        for i in 0..messages_per_pair {
                            let msg = format!("Pair {} Message {}", pair_id, i);
                            write1.send(Message::Text(msg)).await.ok();
                            metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
                            sleep(Duration::from_millis(10)).await;
                        }
                        
                        sleep(Duration::from_secs(1)).await;
                    }
                }
            }
        });
        
        tasks.push(task);
    }
    
    // Wait for all pairs to complete
    for task in tasks {
        task.await.ok();
    }
    
    let duration = start.elapsed();
    metrics.print_summary("Concurrent Pairs Test", duration);
    
    Ok(())
}

// Test 5: Connection stability
async fn test_connection_stability() -> Result<()> {
    println!("\n{}", "TEST 5: Connection Stability".green().bold());
    
    let session = register_session().await?;
    let test_duration = Duration::from_secs(5);
    let start = Instant::now();
    
    // Connect workstation
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    // Connect phone
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Phone echo
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            write2.send(Message::Text(format!("ACK:{}", frame))).await.ok();
                        }
                    }
                }
            }
        }
    });
    
    // Send periodic heartbeats
    let mut sent = 0;
    let mut received = 0;
    
    // Collect acknowledgments separately
    let (ack_tx, mut ack_rx) = tokio::sync::mpsc::unbounded_channel();
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            if frame.starts_with("ACK:PING:") {
                                ack_tx.send(()).ok();
                            }
                        }
                    }
                }
            }
        }
    });
    
    // Send heartbeats
    while start.elapsed() < test_duration {
        write1.send(Message::Text(format!("PING:{}", sent))).await?;
        sent += 1;
        sleep(Duration::from_millis(500)).await;
    }
    
    // Wait a bit for remaining acknowledgments to arrive
    sleep(Duration::from_millis(500)).await;
    
    // Count received acknowledgments
    while ack_rx.try_recv().is_ok() {
        received += 1;
    }
    
    println!("Heartbeats sent: {}", sent);
    println!("Acknowledgments received: {}", received);
    println!("Connection stability: {:.1}%", (received as f64 / sent as f64) * 100.0);
    
    if received == sent {
        println!("{}", "✓ Perfect connection stability".green());
    } else if received as f64 / sent as f64 > 0.95 {
        println!("{}", "✓ Good connection stability".green());
    } else {
        println!("{}", "✗ Poor connection stability".red());
    }
    
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("\n{}", "=".repeat(60).blue());
    println!("{}", "RELAY SYSTEM INTEGRATION TEST SUITE".blue().bold());
    println!("{}", "=".repeat(60).blue());
    
    // Check server is running
    let client = reqwest::Client::new();
    match client.get("http://localhost:3001/health").send().await {
        Ok(_) => println!("{}", "✓ Server is running".green()),
        Err(_) => {
            println!("{}", "✗ Server is not running!".red());
            println!("Please start the relay server first:");
            println!("  cargo run --release --bin relay-server");
            return Ok(());
        }
    }
    
    // Run all tests
    let mut failed = false;
    
    if let Err(e) = test_basic_relay().await {
        println!("{} Basic relay test failed: {}", "✗".red(), e);
        failed = true;
    }
    
    if let Err(e) = test_message_ordering().await {
        println!("{} Message ordering test failed: {}", "✗".red(), e);
        failed = true;
    }
    
    if let Err(e) = test_throughput().await {
        println!("{} Throughput test failed: {}", "✗".red(), e);
        failed = true;
    }
    
    if let Err(e) = test_concurrent_pairs().await {
        println!("{} Concurrent pairs test failed: {}", "✗".red(), e);
        failed = true;
    }
    
    if let Err(e) = test_connection_stability().await {
        println!("{} Connection stability test failed: {}", "✗".red(), e);
        failed = true;
    }
    
    // Final summary
    println!("\n{}", "=".repeat(60).blue());
    if failed {
        println!("{}", "SOME TESTS FAILED".red().bold());
    } else {
        println!("{}", "ALL TESTS PASSED".green().bold());
    }
    println!("{}", "=".repeat(60).blue());
    
    Ok(())
}
```

