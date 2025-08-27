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