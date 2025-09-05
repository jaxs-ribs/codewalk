use anyhow::Result;
use async_trait::async_trait;
use crate::session::{SessionContext, SessionHistory, SessionEvent};
use uuid::Uuid;

#[async_trait]
pub trait SessionStore: Send + Sync {
    async fn save_session(&self, context: &SessionContext, history: &SessionHistory) -> Result<()>;
    
    async fn load_session(&self, session_id: Uuid) -> Result<(SessionContext, SessionHistory)>;
    
    async fn list_sessions(&self, user_id: Option<&str>) -> Result<Vec<SessionMetadata>>;
    
    async fn delete_session(&self, session_id: Uuid) -> Result<()>;
    
    async fn append_event(&self, session_id: Uuid, event: SessionEvent) -> Result<()>;
    
    async fn session_exists(&self, session_id: Uuid) -> Result<bool>;
}

#[derive(Debug, Clone)]
pub struct SessionMetadata {
    pub session_id: Uuid,
    pub user_id: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub status: String,
    pub event_count: usize,
}