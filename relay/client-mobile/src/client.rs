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