use anyhow::Result;
use async_trait::async_trait;
use crate::session::SessionHistory;

#[async_trait]
pub trait Summarizer: Send + Sync {
    async fn summarize_session(&self, history: &SessionHistory) -> Result<SessionSummaryOutput>;
    
    async fn extract_key_events(&self, history: &SessionHistory) -> Result<Vec<KeyEvent>>;
    
    async fn generate_title(&self, history: &SessionHistory) -> Result<String>;
}

#[derive(Debug, Clone)]
pub struct SessionSummaryOutput {
    pub title: String,
    pub summary: String,
    pub key_points: Vec<String>,
    pub actions_taken: Vec<String>,
    pub outcomes: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct KeyEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub description: String,
    pub importance: EventImportance,
}

#[derive(Debug, Clone, Copy)]
pub enum EventImportance {
    Low,
    Medium,
    High,
    Critical,
}