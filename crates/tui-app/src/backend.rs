use anyhow::Result;
use std::sync::Arc;
use tokio::sync::Mutex;

use audio_transcribe::{AudioRecorder, TranscriptionProvider, GroqProvider as AudioGroqProvider};
use llm_interface::{LLMProvider, PlanExtractor, JsonPlanExtractor, GroqProvider as LLMGroqProvider, CommandPlan, RouterResponse};

// Store providers and components as thread-local or global state
thread_local! {
    static AUDIO_RECORDER: std::cell::RefCell<Option<AudioRecorder>> = std::cell::RefCell::new(None);
}

lazy_static::lazy_static! {
    static ref TRANSCRIPTION_PROVIDER: Arc<Mutex<Option<Box<dyn TranscriptionProvider>>>> = Arc::new(Mutex::new(None));
    static ref LLM_PROVIDER: Arc<Mutex<Option<Box<dyn LLMProvider>>>> = Arc::new(Mutex::new(None));
    static ref PLAN_EXTRACTOR: Arc<Mutex<JsonPlanExtractor>> = Arc::new(Mutex::new(JsonPlanExtractor::new()));
}

pub async fn initialize_backend(api_key: String) -> Result<()> {
    // Initialize audio recorder
    AUDIO_RECORDER.with(|r| {
        *r.borrow_mut() = Some(AudioRecorder::new()?);
        Ok::<(), anyhow::Error>(())
    })?;
    
    // Initialize transcription provider (Groq)
    let mut groq_provider = Box::new(AudioGroqProvider::new());
    let config = serde_json::json!({
        "api_key": api_key
    });
    groq_provider.initialize(config.clone()).await?;
    
    let mut provider_guard = TRANSCRIPTION_PROVIDER.lock().await;
    *provider_guard = Some(groq_provider);
    
    // Initialize LLM provider (Groq for routing)
    let mut llm_provider = Box::new(LLMGroqProvider::new());
    llm_provider.initialize(config).await?;
    
    let mut llm_guard = LLM_PROVIDER.lock().await;
    *llm_guard = Some(llm_provider);
    
    Ok(())
}

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

pub async fn take_recorded_audio() -> Result<Vec<u8>> {
    AUDIO_RECORDER.with(|r| {
        if let Some(recorder) = r.borrow_mut().as_mut() {
            let samples = recorder.stop_recording()?;
            
            if samples.is_empty() {
                return Ok(Vec::new());
            }
            
            recorder.samples_to_wav(&samples)
        } else {
            Ok(Vec::new())
        }
    })
}

pub async fn voice_to_text(audio: Vec<u8>) -> Result<String> {
    if audio.is_empty() {
        return Ok(String::new());
    }
    
    let provider_guard = TRANSCRIPTION_PROVIDER.lock().await;
    
    if let Some(provider) = provider_guard.as_ref() {
        let result = provider.transcribe(audio).await?;
        Ok(result.text)
    } else {
        Ok(String::new())
    }
}

pub async fn text_to_llm_cmd(text: &str) -> Result<String> {
    let provider_guard = LLM_PROVIDER.lock().await;
    
    if let Some(provider) = provider_guard.as_ref() {
        provider.text_to_plan(text).await
    } else {
        Err(anyhow::anyhow!("LLM provider not initialized"))
    }
}

pub async fn extract_command_plan(json_str: &str) -> Result<CommandPlan> {
    let extractor = PLAN_EXTRACTOR.lock().await;
    extractor.extract_plan(json_str)
}

pub async fn extract_cmd(json_str: &str) -> Result<String> {
    let extractor = PLAN_EXTRACTOR.lock().await;
    extractor.extract_first_command(json_str)?
        .ok_or_else(|| anyhow::anyhow!("No command found in plan"))
}

pub async fn parse_router_response(json_str: &str) -> Result<RouterResponse> {
    let response: RouterResponse = serde_json::from_str(json_str)?;
    Ok(response)
}