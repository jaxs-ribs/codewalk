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
    /// Kill an existing session and exit
    #[clap(long, value_parser)]
    kill: Option<String>,
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
    
    if let Some(session_id) = &args.kill {
        let url = format!("{}/api/session/{}", args.server_url, session_id);
        let client = reqwest::Client::new();
        let resp = client.delete(&url).send().await?;
        if resp.status().is_success() {
            println!("Session {} killed ({}).", session_id, resp.status());
            return Ok(());
        } else {
            println!("Failed to kill session {} ({}).", session_id, resp.status());
            std::process::exit(1);
        }
    }
    
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
    let (write, mut read) = ws_stream.split();
    
    let hello = HelloMessage {
        msg_type: "hello".to_string(),
        s: register_data.session_id.clone(),
        t: register_data.token.clone(),
        r: "workstation".to_string(),
    };
    
    use std::sync::Arc;
    let write = Arc::new(tokio::sync::Mutex::new(write));
    {
        let mut guard = write.lock().await;
        guard.send(Message::Text(serde_json::to_string(&hello)?)).await?;
    }
    info!("Sent hello message, waiting for acknowledgment...");
    
    // Start heartbeat task
    let hb_secs: u64 = std::env::var("HEARTBEAT_INTERVAL_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(30);
    let write_clone = write.clone();
    tokio::spawn(async move {
        let payload = r#"{"type":"hb"}"#;
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(hb_secs)).await;
            let mut guard = write_clone.lock().await;
            if guard.send(Message::Text(payload.to_string())).await.is_err() {
                break;
            }
        }
    });

    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin);
    let write_clone2 = write.clone();

    println!("\n[Workstation] Connected! Waiting for mobile client...");
    println!("Type messages to send (press Enter to send):");

    // Reader task for server messages
    let read_task = tokio::spawn(async move {
        while let Some(msg) = read.next().await {
            match msg {
                Ok(Message::Text(text)) => {
                    if let Ok(server_msg) = serde_json::from_str::<ServerMessage>(&text) {
                        match server_msg.msg_type.as_str() {
                            "hello-ack" => info!("Connection acknowledged"),
                            "peer-joined" => println!("[System] Mobile client connected!"),
                            "peer-left" => println!("[System] Mobile client disconnected"),
                            "session-killed" => {
                                println!("[System] Session was killed by workstation. Closing.");
                                break;
                            }
                            _ => {}
                        }
                    } else {
                        println!("[Mobile] {}", text);
                    }
                }
                Ok(Message::Binary(data)) => println!("[Mobile] Received {} bytes of binary data", data.len()),
                Ok(Message::Close(_)) => {
                    println!("[System] Connection closed");
                    break;
                }
                Err(e) => {
                    eprintln!("WebSocket error: {}", e);
                    break;
                }
                _ => {}
            }
        }
    });

    // Stdin loop for sending
    let mut input_buffer = String::new();
    loop {
        if reader.read_line(&mut input_buffer).await.is_err() {
            break;
        }
        if !input_buffer.trim().is_empty() {
            let mut guard = write_clone2.lock().await;
            guard.send(Message::Text(input_buffer.trim().to_string())).await?;
            print!("[You] {}", input_buffer);
            io::stdout().flush()?;
        }
        input_buffer.clear();
    }

    let _ = read_task.await;
    
    Ok(())
}
