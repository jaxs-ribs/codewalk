use anyhow::Result;
use serde_json::Value;

pub fn record_voice(_start: bool) -> Result<()> {
    Ok(())
}

pub fn take_recorded_audio() -> Result<Vec<u8>> {
    Ok(vec![1, 2, 3])
}

pub fn voice_to_text(_audio: Vec<u8>) -> Result<String> {
    Ok("connect to bandit level zero and read readme".to_string())
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