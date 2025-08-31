use anyhow::Result;
use async_trait::async_trait;
use tokio::sync::mpsc;

use orchestrator_core::ports::{RouterPort, RouteResponse, RouteAction, ExecutorPort, OutboundPort};

use crate::backend;

pub struct RouterAdapter;

#[async_trait]
impl RouterPort for RouterAdapter {
    async fn route(&self, text: &str) -> Result<RouteResponse> {
        // Use existing backend LLM routing and map to core types
        let json = backend::text_to_llm_cmd(text).await?;
        let resp = backend::parse_router_response(&json).await?;
        let action = match resp.action {
            router::RouterAction::LaunchClaude => RouteAction::LaunchClaude,
            router::RouterAction::CannotParse => RouteAction::CannotParse,
        };
        Ok(RouteResponse {
            action,
            prompt: resp.prompt,
            reason: resp.reason,
            confidence: Some(resp.confidence),
        })
    }
}

/// For Phase 3 we only use confirmation path; launching remains in the TUI.
pub struct NoopExecutor;
#[async_trait]
impl ExecutorPort for NoopExecutor {
    async fn launch(&self, _prompt: &str) -> Result<()> { Ok(()) }
}

#[derive(Clone)]
pub struct OutboundChannel(pub mpsc::Sender<protocol::Message>);
#[async_trait]
impl OutboundPort for OutboundChannel {
    async fn send(&self, msg: protocol::Message) -> Result<()> {
        self.0.send(msg).await.map_err(|e| anyhow::anyhow!(e.to_string()))
    }
}

pub struct CoreHandles {
    pub inbound_tx: mpsc::Sender<protocol::Message>,
    pub outbound_rx: mpsc::Receiver<protocol::Message>,
}

pub fn start_core() -> CoreHandles {
    let (in_tx, mut in_rx) = mpsc::channel::<protocol::Message>(100);
    let (out_tx, out_rx) = mpsc::channel::<protocol::Message>(100);

    let core = orchestrator_core::OrchestratorCore::new(
        RouterAdapter,
        NoopExecutor,
        OutboundChannel(out_tx.clone()),
    );
    // Keep confirmation required; TUI will launch on confirm
    let core = std::sync::Arc::new(core);

    // Spawn processor loop
    let core_task = core.clone();
    tokio::spawn(async move {
        while let Some(msg) = in_rx.recv().await {
            let _ = core_task.handle(msg).await;
        }
    });

    CoreHandles { inbound_tx: in_tx, outbound_rx: out_rx }
}

