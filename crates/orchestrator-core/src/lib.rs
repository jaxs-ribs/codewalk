pub mod ports;

use anyhow::Result;
use ports::{ExecutorPort, OutboundPort, RouteAction, RouterPort};

/// Headless orchestrator core: consumes protocol messages, emits protocol messages.
pub struct OrchestratorCore<R: RouterPort, E: ExecutorPort, O: OutboundPort> {
    router: R,
    executor: E,
    outbound: O,
    require_confirmation: bool,
}

impl<R: RouterPort, E: ExecutorPort, O: OutboundPort> OrchestratorCore<R, E, O> {
    pub fn new(router: R, executor: E, outbound: O) -> Self {
        Self { router, executor, outbound, require_confirmation: true }
    }

    pub fn set_require_confirmation(&mut self, yes: bool) { self.require_confirmation = yes; }

    /// Entry point for inbound messages (Phase 2: handle user_text only)
    pub async fn handle(&self, msg: protocol::Message) -> Result<()> {
        match msg {
            protocol::Message::UserText(ut) => self.handle_user_text(ut).await,
            protocol::Message::Ack(_) => Ok(()), // ignore inbound acks
            protocol::Message::Status(_) => Ok(()),
            protocol::Message::PromptConfirmation(_) => Ok(()),
        }
    }

    async fn handle_user_text(&self, ut: protocol::UserText) -> Result<()> {
        let text = ut.text.trim();
        if text.is_empty() { return Ok(()); }

        // Route the text
        let decision = self.router.route(text).await?;
        match decision.action {
            RouteAction::CannotParse => {
                let reason = decision.reason.unwrap_or_else(|| "could not understand".to_string());
                self.outbound.send(protocol::Message::Status(protocol::Status {
                    v: Some(protocol::VERSION),
                    level: "info".to_string(),
                    text: reason,
                })).await
            }
            RouteAction::LaunchClaude => {
                let prompt = decision.prompt.unwrap_or_else(|| text.to_string());
                if self.require_confirmation {
                    self.outbound.send(protocol::Message::PromptConfirmation(protocol::PromptConfirmation {
                        v: Some(protocol::VERSION),
                        for_: "executor_launch".to_string(),
                        executor: "Claude".to_string(),
                        working_dir: None,
                        prompt,
                    })).await
                } else {
                    // Launch immediately
                    self.executor.launch(&prompt).await?;
                    self.outbound.send(protocol::Message::Status(protocol::Status {
                        v: Some(protocol::VERSION),
                        level: "info".to_string(),
                        text: format!("executor started: Claude"),
                    })).await
                }
            }
        }
    }
}

// Simple in-crate mocks for demo/testing
pub mod mocks {
    use super::*;
    use async_trait::async_trait;
    use tokio::sync::mpsc;

    pub struct MockRouter;
    #[async_trait]
    impl RouterPort for MockRouter {
        async fn route(&self, text: &str) -> Result<ports::RouteResponse> {
            let text_l = text.to_lowercase();
            if text_l.contains("code") || text_l.contains("build") || text_l.contains("refactor") {
                Ok(ports::RouteResponse {
                    action: ports::RouteAction::LaunchClaude,
                    prompt: Some(text.to_string()),
                    reason: None,
                    confidence: Some(0.8),
                })
            } else {
                Ok(ports::RouteResponse {
                    action: ports::RouteAction::CannotParse,
                    prompt: None,
                    reason: Some("Non-coding or unclear".to_string()),
                    confidence: Some(0.5),
                })
            }
        }
    }

    pub struct MockExecutor;
    #[async_trait]
    impl ExecutorPort for MockExecutor {
        async fn launch(&self, _prompt: &str) -> Result<()> { Ok(()) }
    }

    #[derive(Clone)]
    pub struct ChannelOutbound(pub mpsc::Sender<protocol::Message>);
    #[async_trait]
    impl OutboundPort for ChannelOutbound {
        async fn send(&self, msg: protocol::Message) -> Result<()> {
            self.0.send(msg).await.map_err(|e| anyhow::anyhow!(e.to_string()))
        }
    }
}
