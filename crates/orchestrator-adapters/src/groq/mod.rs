use anyhow::Result;
use std::sync::Arc;
use tokio::sync::Mutex;

use router::{LLMProvider, GroqProvider as LLMGroqProvider, RouterResponse};

#[cfg(feature = "tui-stt")]
use stt::{AudioRecorder, TranscriptionProvider, GroqProvider as AudioGroqProvider};

// Store providers and components as thread-local or global state
#[cfg(feature = "tui-stt")]
thread_local! {
    static AUDIO_RECORDER: std::cell::RefCell<Option<AudioRecorder>> = std::cell::RefCell::new(None);
}

#[cfg(feature = "tui-stt")]
lazy_static::lazy_static! {
    static ref TRANSCRIPTION_PROVIDER: Arc<Mutex<Option<Box<dyn TranscriptionProvider>>>> = Arc::new(Mutex::new(None));
}

lazy_static::lazy_static! {
    static ref LLM_PROVIDER: Arc<Mutex<Option<Box<dyn LLMProvider>>>> = Arc::new(Mutex::new(None));
}

pub async fn initialize_backend(api_key: String) -> Result<()> {
    let config = serde_json::json!({ "api_key": api_key });

    // Initialize LLM provider (Groq for routing)
    let mut llm_provider = Box::new(LLMGroqProvider::new());
    llm_provider.initialize(config.clone()).await?;
    let mut llm_guard = LLM_PROVIDER.lock().await;
    *llm_guard = Some(llm_provider);

    // Optionally initialize local STT (TUI microphone)
    #[cfg(feature = "tui-stt")]
    {
        // Initialize audio recorder
        AUDIO_RECORDER.with(|r| {
            *r.borrow_mut() = Some(AudioRecorder::new()?);
            Ok::<(), anyhow::Error>(())
        })?;
        // Initialize transcription provider (Groq)
        let mut groq_provider = Box::new(AudioGroqProvider::new());
        groq_provider.initialize(config).await?;
        let mut provider_guard = TRANSCRIPTION_PROVIDER.lock().await;
        *provider_guard = Some(groq_provider);
    }

    Ok(())
}

#[cfg(feature = "tui-stt")]
pub async fn record_voice(start: bool) -> Result<()> {
    AUDIO_RECORDER.with(|r| {
        if let Some(recorder) = r.borrow_mut().as_mut() {
            if start {
                recorder.start_recording()?;
            }
        }
        Ok(())
    })
}

#[cfg(not(feature = "tui-stt"))]
pub async fn record_voice(_start: bool) -> Result<()> { Ok(()) }

#[cfg(feature = "tui-stt")]
pub async fn take_recorded_audio() -> Result<Vec<u8>> {
    AUDIO_RECORDER.with(|r| {
        if let Some(recorder) = r.borrow_mut().as_mut() {
            let samples = recorder.stop_recording()?;
            if samples.is_empty() { return Ok(Vec::new()); }
            recorder.samples_to_wav(&samples)
        } else {
            Ok(Vec::new())
        }
    })
}

#[cfg(not(feature = "tui-stt"))]
pub async fn take_recorded_audio() -> Result<Vec<u8>> { Ok(Vec::new()) }

#[cfg(feature = "tui-stt")]
pub async fn voice_to_text(audio: Vec<u8>) -> Result<String> {
    if audio.is_empty() { return Ok(String::new()); }
    let provider_guard = TRANSCRIPTION_PROVIDER.lock().await;
    if let Some(provider) = provider_guard.as_ref() {
        let result = provider.transcribe(audio).await?;
        Ok(result.text)
    } else {
        Ok(String::new())
    }
}

#[cfg(not(feature = "tui-stt"))]
pub async fn voice_to_text(_audio: Vec<u8>) -> Result<String> { Ok(String::new()) }

pub async fn text_to_llm_cmd(text: &str) -> Result<String> {
    let mut provider_guard = LLM_PROVIDER.lock().await;
    
    if let Some(provider) = provider_guard.as_mut() {
        provider.text_to_plan(text).await
    } else {
        Err(anyhow::anyhow!("LLM provider not initialized"))
    }
}

pub async fn parse_router_response(json_str: &str) -> Result<RouterResponse> {
    let response: RouterResponse = serde_json::from_str(json_str)?;
    Ok(response)
}

/// Summarize text using Groq LLM
pub async fn summarize_with_groq(system_prompt: &str, user_prompt: &str) -> Result<String> {
    // Use llm crate directly for summarization
    let client = llm::Client::from_env_groq("llama-3.1-8b-instant")?;
    
    let messages = vec![
        llm::ChatMessage {
            role: llm::Role::System,
            content: system_prompt.to_string(),
        },
        llm::ChatMessage {
            role: llm::Role::User,
            content: user_prompt.to_string(),
        },
    ];
    
    let options = llm::ChatOptions {
        temperature: Some(0.3),
        json_object: false,
    };
    
    client.chat(&messages, options).await
}
