use anyhow::Result;
use serde_json::Value;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::groq::GroqClient;

// Store audio recorder and groq client as thread-local since audio recorder isn't Send
thread_local! {
    static AUDIO_RECORDER: std::cell::RefCell<Option<crate::audio::AudioRecorder>> = std::cell::RefCell::new(None);
}

lazy_static::lazy_static! {
    static ref GROQ_CLIENT: Arc<Mutex<Option<GroqClient>>> = Arc::new(Mutex::new(None));
}

pub async fn initialize_backend(api_key: String) -> Result<()> {
    // Initialize audio recorder in thread-local storage
    AUDIO_RECORDER.with(|r| {
        *r.borrow_mut() = Some(crate::audio::AudioRecorder::new()?);
        Ok::<(), anyhow::Error>(())
    })?;
    
    let mut client_guard = GROQ_CLIENT.lock().await;
    *client_guard = Some(GroqClient::new(api_key)?);
    
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
            
            // Use the actual sample rate from the device
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
    
    let client_guard = GROQ_CLIENT.lock().await;
    
    if let Some(client) = client_guard.as_ref() {
        client.transcribe(audio).await
    } else {
        Ok(String::new())
    }
}

pub fn text_to_llm_cmd(text: &str) -> Result<String> {
    if text.contains("bandit") {
        Ok(r#"{"status":"ok","confidence":{"score":0.8,"label":"high"},"plan":{"cwd":"~","explanation":"SSH then print README","steps":[{"cmd":"ssh bandit0@bandit.labs.overthewire.org -p 2220"},{"cmd":"cat readme"}]}}"#.to_string())
    } else {
        Ok(format!(
            r#"{{"status":"ok","plan":{{"steps":[{{"cmd":"echo 'Simulated command for: {}'"}}]}}}}"#,
            text
        ))
    }
}

pub fn extract_cmd(plan_json: &str) -> Result<String> {
    let json: Value = serde_json::from_str(plan_json)?;
    
    json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .and_then(|steps| steps.first())
        .and_then(|step| step.get("cmd"))
        .and_then(|c| c.as_str())
        .map(String::from)
        .ok_or_else(|| anyhow::anyhow!("Could not extract command from plan"))
}

pub fn parse_plan_json(json_str: &str) -> Result<PlanInfo> {
    let json: Value = serde_json::from_str(json_str)?;
    
    let status = json.get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("");
    
    let reason = json.get("reason")
        .and_then(|r| r.as_str())
        .map(String::from);
    
    let has_steps = json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .is_some();
    
    let explanation = json.get("plan")
        .and_then(|p| p.get("explanation"))
        .and_then(|e| e.as_str())
        .map(String::from);
    
    let step_count = json.get("plan")
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_array())
        .map(|steps| steps.len())
        .unwrap_or(0);
    
    Ok(PlanInfo {
        status: status.to_string(),
        reason,
        has_steps,
        explanation,
        step_count,
    })
}

pub struct PlanInfo {
    pub status: String,
    pub reason: Option<String>,
    pub has_steps: bool,
    #[allow(dead_code)]
    pub explanation: Option<String>,
    #[allow(dead_code)]
    pub step_count: usize,
}