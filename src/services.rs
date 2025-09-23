use std::{fs, path::Path, time::Duration};

use anyhow::{Context, Result, anyhow};
use reqwest::blocking::{Client as HttpClient, multipart};
use serde::Deserialize;
use serde_json::json;

use crate::{
    DEFAULT_LLM_MAX_TOKENS, DEFAULT_LLM_MODEL, DEFAULT_LLM_TEMPERATURE, DEFAULT_STT_LANGUAGE,
    SMART_SECRETARY_PROMPT,
};

pub struct TranscriptionClient {
    http: HttpClient,
    base_url: String,
    api_key: String,
    language: String,
}

impl TranscriptionClient {
    pub fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq transcription")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());
        let language =
            std::env::var("GROQ_STT_LANGUAGE").unwrap_or_else(|_| DEFAULT_STT_LANGUAGE.to_string());

        Ok(Self {
            http,
            base_url,
            api_key,
            language,
        })
    }

    pub fn transcribe(&self, audio_path: &Path) -> Result<String> {
        let audio_bytes = fs::read(audio_path)
            .with_context(|| format!("Failed to read audio file {}", audio_path.display()))?;

        let file_name = audio_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("audio.wav");

        let part = multipart::Part::bytes(audio_bytes)
            .file_name(file_name.to_string())
            .mime_str("audio/wav")
            .context("Failed to prepare audio part for transcription")?;

        let form = multipart::Form::new()
            .text("model", "whisper-large-v3-turbo")
            .text("language", self.language.clone())
            .text("response_format", "json")
            .part("file", part);

        let url = format!(
            "{}/openai/v1/audio/transcriptions",
            self.base_url.trim_end_matches('/')
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
            .multipart(form)
            .send()
            .context("Groq transcription request failed")?;

        let response = response
            .error_for_status()
            .context("Groq transcription returned an error status")?;

        let payload: TranscriptionResponse = response
            .json()
            .context("Failed to parse Groq transcription response")?;

        if payload.text.trim().is_empty() {
            Err(anyhow!("Groq transcription response was empty"))
        } else {
            Ok(payload.text)
        }
    }
}

#[derive(Debug, Deserialize)]
struct TranscriptionResponse {
    text: String,
}

pub struct AssistantClient {
    http: HttpClient,
    base_url: String,
    api_key: String,
    model: String,
    temperature: f32,
    max_tokens: u32,
}

impl AssistantClient {
    pub fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq assistant")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());

        let model =
            std::env::var("GROQ_LLM_MODEL").unwrap_or_else(|_| DEFAULT_LLM_MODEL.to_string());

        let temperature = std::env::var("GROQ_LLM_TEMPERATURE")
            .ok()
            .and_then(|val| val.parse::<f32>().ok())
            .unwrap_or(DEFAULT_LLM_TEMPERATURE);

        let max_tokens = std::env::var("GROQ_LLM_MAX_TOKENS")
            .ok()
            .and_then(|val| val.parse::<u32>().ok())
            .unwrap_or(DEFAULT_LLM_MAX_TOKENS);

        Ok(Self {
            http,
            base_url,
            api_key,
            model,
            temperature,
            max_tokens,
        })
    }

    pub fn reply(&self, transcript: &str) -> Result<String> {
        self.reply_with_context(transcript, &[])
    }
    
    pub fn reply_with_context(&self, transcript: &str, context: &[String]) -> Result<String> {
        let mut messages = vec![
            json!({"role": "system", "content": SMART_SECRETARY_PROMPT}),
        ];
        
        // Add conversation history if provided
        if !context.is_empty() {
            let context_str = context.join("\n");
            messages.push(json!({
                "role": "system",
                "content": format!("Recent conversation history:\n{}", context_str)
            }));
        }
        
        messages.push(json!({"role": "user", "content": transcript}));
        
        let body = json!({
            "model": self.model,
            "messages": messages,
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "stream": false
        });

        let url = format!(
            "{}/openai/v1/chat/completions",
            self.base_url.trim_end_matches('/')
        );

        // Try with retry on network/server errors
        let mut retries = 2;
        loop {
            let result = self
                .http
                .post(&url)
                .bearer_auth(&self.api_key)
                .json(&body)
                .send();
                
            match result {
                Ok(response) => {
                    match response.error_for_status() {
                        Ok(resp) => {
                            match resp.json::<AssistantResponse>() {
                                Ok(payload) => {
                                    let reply = payload
                                        .choices
                                        .into_iter()
                                        .find_map(|choice| choice.message.content)
                                        .unwrap_or_default();

                                    if reply.trim().is_empty() {
                                        return Err(anyhow!("Groq assistant response was empty"));
                                    } else {
                                        return Ok(reply);
                                    }
                                }
                                Err(e) => {
                                    if retries > 0 {
                                        retries -= 1;
                                        eprintln!("[assistant] Parse error, retrying: {}", e);
                                        std::thread::sleep(std::time::Duration::from_millis(500));
                                        continue;
                                    }
                                    // Fallback response
                                    return Ok("Let's continue our conversation".to_string());
                                }
                            }
                        }
                        Err(e) => {
                            if retries > 0 && (e.status() == Some(reqwest::StatusCode::SERVICE_UNAVAILABLE)
                                || e.status() == Some(reqwest::StatusCode::GATEWAY_TIMEOUT)
                                || e.status() == Some(reqwest::StatusCode::TOO_MANY_REQUESTS)) {
                                retries -= 1;
                                eprintln!("[assistant] HTTP error {}, retrying...", e.status().unwrap());
                                std::thread::sleep(std::time::Duration::from_millis(1000));
                                continue;
                            }
                            // Fallback response on non-retryable errors
                            eprintln!("[assistant] LLM error: {}", e);
                            return Ok("I understand. Please continue".to_string());
                        }
                    }
                }
                Err(e) => {
                    if retries > 0 {
                        retries -= 1;
                        eprintln!("[assistant] Network error, retrying: {}", e);
                        std::thread::sleep(std::time::Duration::from_millis(1000));
                        continue;
                    }
                    // Fallback response on network failure
                    eprintln!("[assistant] Network failure: {}", e);
                    return Ok("I understand. Please continue".to_string());
                }
            }
        }
    }
}

#[derive(Debug, Deserialize)]
struct AssistantResponse {
    choices: Vec<AssistantChoice>,
}

#[derive(Debug, Deserialize)]
struct AssistantChoice {
    message: AssistantMessage,
}

#[derive(Debug, Deserialize)]
struct AssistantMessage {
    content: Option<String>,
}
