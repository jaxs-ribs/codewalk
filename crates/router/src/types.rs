use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouterResponse {
    pub action: RouterAction,
    pub prompt: Option<String>,
    pub reason: Option<String>,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RouterAction {
    LaunchClaude,
    CannotParse,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandPlan {
    pub status: PlanStatus,
    pub confidence: Option<PlanConfidence>,
    pub plan: Option<Plan>,
    pub reason: Option<String>,
    pub raw_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plan {
    pub cwd: Option<String>,
    pub explanation: Option<String>,
    pub steps: Vec<PlanStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub cmd: String,
    pub description: Option<String>,
    pub expected_output: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PlanStatus {
    Ok,
    Deny,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanConfidence {
    pub score: f32,
    pub label: String,
}

impl CommandPlan {
    pub fn is_valid(&self) -> bool {
        self.status == PlanStatus::Ok && self.plan.is_some()
    }

    pub fn get_first_command(&self) -> Option<String> {
        self.plan.as_ref()
            .and_then(|p| p.steps.first())
            .map(|s| s.cmd.clone())
    }

    pub fn get_all_commands(&self) -> Vec<String> {
        self.plan.as_ref()
            .map(|p| p.steps.iter().map(|s| s.cmd.clone()).collect())
            .unwrap_or_default()
    }
}