use anyhow::{Result, anyhow};
use async_trait::async_trait;
use reqwest::multipart;
use serde::Deserialize;
use crate::interfaces::TranscriptionService;
use crate::constants::{GROQ_API_ENDPOINT, GROQ_MODEL, GROQ_RESPONSE_FORMAT, GROQ_LANGUAGE};

#[derive(Debug, Deserialize)]
struct TranscriptionResponse {
    text: String,
}

pub struct GroqTranscriptionService {
    client: reqwest::Client,
    api_key: String,
}

impl GroqTranscriptionService {
    pub fn new(api_key: String) -> Result<Self> {
        Ok(Self {
            client: reqwest::Client::new(),
            api_key,
        })
    }
}

#[async_trait]
impl TranscriptionService for GroqTranscriptionService {
    async fn transcribe(&self, audio_data: Vec<u8>) -> Result<String> {
        let request = TranscriptionRequest::new(audio_data)?;
        let response = request.send(&self.client, &self.api_key).await?;
        ResponseHandler::extract_text(response).await
    }
}

struct TranscriptionRequest {
    form: multipart::Form,
}

impl TranscriptionRequest {
    fn new(audio_data: Vec<u8>) -> Result<Self> {
        let form = FormBuilder::build_transcription_form(audio_data)?;
        Ok(Self { form })
    }

    async fn send(self, client: &reqwest::Client, api_key: &str) -> Result<reqwest::Response> {
        client
            .post(GROQ_API_ENDPOINT)
            .header("Authorization", format!("Bearer {}", api_key))
            .multipart(self.form)
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send transcription request: {}", e))
    }
}

struct FormBuilder;

impl FormBuilder {
    fn build_transcription_form(audio_data: Vec<u8>) -> Result<multipart::Form> {
        let audio_part = Self::create_audio_part(audio_data)?;
        
        let form = multipart::Form::new()
            .text("model", GROQ_MODEL)
            .text("response_format", GROQ_RESPONSE_FORMAT)
            .text("language", GROQ_LANGUAGE)
            .part("file", audio_part);
        
        Ok(form)
    }

    fn create_audio_part(audio_data: Vec<u8>) -> Result<multipart::Part> {
        multipart::Part::bytes(audio_data)
            .file_name("audio.wav")
            .mime_str("audio/wav")
            .map_err(|e| anyhow!("Failed to create audio part: {}", e))
    }
}

struct ResponseHandler;

impl ResponseHandler {
    async fn extract_text(response: reqwest::Response) -> Result<String> {
        Self::validate_status(&response)?;
        Self::parse_response(response).await
    }

    fn validate_status(response: &reqwest::Response) -> Result<()> {
        if !response.status().is_success() {
            return Err(anyhow!(
                "Transcription API returned error status: {}",
                response.status()
            ));
        }
        Ok(())
    }

    async fn parse_response(response: reqwest::Response) -> Result<String> {
        let transcription: TranscriptionResponse = response
            .json()
            .await
            .map_err(|e| anyhow!("Failed to parse transcription response: {}", e))?;
        
        Ok(transcription.text)
    }
}