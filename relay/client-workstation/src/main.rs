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