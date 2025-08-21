use anyhow::{Result, anyhow};
use reqwest::multipart;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct TranscriptionResponse {
    text: String,
}

pub struct GroqClient {
    client: reqwest::Client,
    api_key: String,
}

impl GroqClient {
    pub fn new(api_key: String) -> Result<Self> {
        Ok(Self {
            client: reqwest::Client::new(),
            api_key,
        })
    }

    pub async fn transcribe(&self, wav_data: Vec<u8>) -> Result<String> {
        let form = build_transcription_form(wav_data)?;
        let response = send_transcription_request(&self.client, &self.api_key, form).await?;
        handle_transcription_response(response).await
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
    
    let transcription: TranscriptionResponse = response.json().await?;
    Ok(transcription.text)
}