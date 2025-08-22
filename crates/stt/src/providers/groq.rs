use anyhow::{Result, anyhow};
use async_trait::async_trait;
use reqwest::multipart;
use serde::Deserialize;

use crate::traits::{TranscriptionProvider, TranscriptionResult};

#[derive(Debug, Deserialize)]
struct GroqResponse {
    text: String,
}

pub struct GroqProvider {
    client: reqwest::Client,
    api_key: Option<String>,
}

impl GroqProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key: None,
        }
    }
}

#[async_trait]
impl TranscriptionProvider for GroqProvider {
    async fn initialize(&mut self, config: serde_json::Value) -> Result<()> {
        let api_key = config.get("api_key")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("Missing api_key in config"))?;
        
        self.api_key = Some(api_key.to_string());
        Ok(())
    }
    
    async fn transcribe(&self, audio_data: Vec<u8>) -> Result<TranscriptionResult> {
        let api_key = self.api_key.as_ref()
            .ok_or_else(|| anyhow!("Provider not initialized"))?;
        
        let form = build_transcription_form(audio_data)?;
        let response = send_transcription_request(&self.client, api_key, form).await?;
        let text = handle_transcription_response(response).await?;
        
        Ok(TranscriptionResult {
            text,
            confidence: None,
            language: Some("en".to_string()),
            duration_ms: None,
        })
    }
    
    fn name(&self) -> &str {
        "groq"
    }
    
    fn is_ready(&self) -> bool {
        self.api_key.is_some()
    }
}

fn build_transcription_form(wav_data: Vec<u8>) -> Result<multipart::Form> {
    let form = multipart::Form::new()
        .text("model", "whisper-large-v3-turbo")
        .text("response_format", "json")
        .text("language", "en")
        .part(
            "file",
            multipart::Part::bytes(wav_data)
                .file_name("audio.wav")
                .mime_str("audio/wav")?
        );
    
    Ok(form)
}

async fn send_transcription_request(
    client: &reqwest::Client,
    api_key: &str,
    form: multipart::Form,
) -> Result<reqwest::Response> {
    let response = client
        .post("https://api.groq.com/openai/v1/audio/transcriptions")
        .header("Authorization", format!("Bearer {}", api_key))
        .multipart(form)
        .send()
        .await?;
    
    Ok(response)
}

async fn handle_transcription_response(response: reqwest::Response) -> Result<String> {
    if !response.status().is_success() {
        let error_text = response.text().await?;
        return Err(anyhow!("Groq API error: {}", error_text));
    }
    
    let transcription: GroqResponse = response.json().await?;
    Ok(transcription.text)
}