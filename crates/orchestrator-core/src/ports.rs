use anyhow::Result;
use async_trait::async_trait;

/// Minimal router decision for Phase 2
#[derive(Debug, Clone, PartialEq)]
pub enum RouteAction {
    LaunchClaude,
    CannotParse,
}

#[derive(Debug, Clone)]
pub struct RouteResponse {
    pub action: RouteAction,
    pub prompt: Option<String>,
    pub reason: Option<String>,
    pub confidence: Option<f32>,
}

#[async_trait]
pub trait RouterPort: Send + Sync {
    async fn route(&self, text: &str) -> Result<RouteResponse>;
}

#[async_trait]
pub trait ExecutorPort: Send + Sync {
    async fn launch(&self, prompt: &str) -> Result<()>;
}

#[async_trait]
pub trait OutboundPort: Send + Sync {
    async fn send(&self, msg: protocol::Message) -> Result<()>;
}

