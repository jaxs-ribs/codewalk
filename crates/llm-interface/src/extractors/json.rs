use anyhow::{Result, anyhow};
use serde_json::Value;

use crate::traits::PlanExtractor;
use crate::types::{CommandPlan, Plan, PlanStep, PlanStatus, PlanConfidence};

pub struct JsonPlanExtractor;

impl JsonPlanExtractor {
    pub fn new() -> Self {
        Self
    }
}

impl PlanExtractor for JsonPlanExtractor {
    fn extract_plan(&self, json_str: &str) -> Result<CommandPlan> {
        let json: Value = serde_json::from_str(json_str)?;
        
        let status = parse_status(&json)?;
        let confidence = parse_confidence(&json);
        let plan = parse_plan(&json);
        let reason = json.get("reason")
            .and_then(|r| r.as_str())
            .map(String::from);
        
        Ok(CommandPlan {
            status,
            confidence,
            plan,
            reason,
            raw_json: json_str.to_string(),
        })
    }
    
    fn extract_first_command(&self, json_str: &str) -> Result<Option<String>> {
        let plan = self.extract_plan(json_str)?;
        Ok(plan.get_first_command())
    }
}

fn parse_status(json: &Value) -> Result<PlanStatus> {
    let status_str = json.get("status")
        .and_then(|s| s.as_str())
        .ok_or_else(|| anyhow!("Missing status field"))?;
    
    match status_str {
        "ok" => Ok(PlanStatus::Ok),
        "deny" => Ok(PlanStatus::Deny),
        _ => Ok(PlanStatus::Error),
    }
}

fn parse_confidence(json: &Value) -> Option<PlanConfidence> {
    json.get("confidence").and_then(|c| {
        let score = c.get("score")?.as_f64()? as f32;
        let label = c.get("label")?.as_str()?.to_string();
        Some(PlanConfidence { score, label })
    })
}

fn parse_plan(json: &Value) -> Option<Plan> {
    let plan_obj = json.get("plan")?;
    let steps = parse_steps(plan_obj)?;
    
    Some(Plan {
        cwd: plan_obj.get("cwd")
            .and_then(|c| c.as_str())
            .map(String::from),
        explanation: plan_obj.get("explanation")
            .and_then(|e| e.as_str())
            .map(String::from),
        steps,
    })
}

fn parse_steps(plan_obj: &Value) -> Option<Vec<PlanStep>> {
    let steps_array = plan_obj.get("steps")?.as_array()?;
    
    let steps: Vec<PlanStep> = steps_array
        .iter()
        .filter_map(|step| {
            let cmd = step.get("cmd")?.as_str()?.to_string();
            let description = step.get("description")
                .and_then(|d| d.as_str())
                .map(String::from);
            let expected_output = step.get("expected_output")
                .and_then(|e| e.as_str())
                .map(String::from);
            
            Some(PlanStep {
                cmd,
                description,
                expected_output,
            })
        })
        .collect();
    
    if steps.is_empty() {
        None
    } else {
        Some(steps)
    }
}