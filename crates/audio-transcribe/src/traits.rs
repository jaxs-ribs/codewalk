use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionResult {
    pub text: String,
    pub confidence: Option<f32>,
    pub language: Option<String>,
    pub duration_ms: Option<u64>,
}

#[async_trait]
pub trait TranscriptionProvider: Send + Sync {
    /// Initialize the provider with necessary configuration
    async fn initialize(&mut self, config: serde_json::Value) -> Result<()>;
    
    /// Transcribe audio data (WAV format) to text
    async fn transcribe(&self, audio_data: Vec<u8>) -> Result<TranscriptionResult>;
    
    /// Get the name of this provider
    fn name(&self) -> &str;
    
    /// Check if the provider is ready
    fn is_ready(&self) -> bool;
}