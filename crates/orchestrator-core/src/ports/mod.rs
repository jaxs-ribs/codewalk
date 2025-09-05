pub mod storage;
pub mod summarizer;
pub mod monitor;

pub use storage::{SessionStore, SessionMetadata};
pub use summarizer::{Summarizer, SessionSummaryOutput, KeyEvent, EventImportance};
pub use monitor::{LogMonitor, LogLevel, SpanId, MetricValue};

use anyhow::Result;
use async_trait::async_trait;

#[derive(Debug, Clone, PartialEq)]
pub enum RouteAction {
    LaunchClaude,
    CannotParse,
    QueryExecutor,
}

#[derive(Debug, Clone)]
pub struct RouteResponse {
    pub action: RouteAction,
    pub prompt: Option<String>,
    pub reason: Option<String>,
    pub confidence: Option<f32>,
}

#[derive(Debug, Clone)]
pub struct RouterContext {
    pub has_active_session: bool,
    pub session_type: Option<String>,
}

#[async_trait]
pub trait RouterPort: Send + Sync {
    async fn route(&self, text: &str, context: Option<RouterContext>) -> Result<RouteResponse>;
}

#[async_trait]
pub trait ExecutorPort: Send + Sync {
    async fn launch(&self, prompt: &str) -> Result<()>;
    async fn query_status(&self) -> Result<String>;
}

#[async_trait]
pub trait OutboundPort: Send + Sync {
    async fn send(&self, msg: protocol::Message) -> Result<()>;
}