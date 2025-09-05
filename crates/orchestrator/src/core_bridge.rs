use anyhow::Result;
use async_trait::async_trait;
use tokio::sync::mpsc;

use orchestrator_core::ports::{RouterPort, RouteResponse, RouteAction, RouterContext, ExecutorPort, OutboundPort};
use tokio::sync::mpsc::Sender;

use crate::backend;

pub struct RouterAdapter;

#[async_trait]
impl RouterPort for RouterAdapter {
    async fn route(&self, text: &str, context: Option<RouterContext>) -> Result<RouteResponse> {
        // Use LLM-based routing with context awareness
        let context_str = if let Some(ctx) = &context {
            if ctx.has_active_session {
                format!("ACTIVE_SESSION: {} is currently running", ctx.session_type.as_deref().unwrap_or("Claude Code"))
            } else {
                "NO_ACTIVE_SESSION".to_string()
            }
        } else {
            "NO_ACTIVE_SESSION".to_string()
        };
        
        // Pass context to the LLM router
        let enhanced_text = format!("[{}] {}", context_str, text);
        let json = backend::text_to_llm_cmd(&enhanced_text).await?;
        let resp = backend::parse_router_response(&json).await?;
        
        // Log router response
        crate::logger::log_event("ROUTER", &format!("Response: action={:?}, reason={:?}", resp.action, resp.reason));
        
        // Map router response, checking for status queries first
        let action = if context.is_some() && context.as_ref().unwrap().has_active_session {
            // If session is active and response suggests checking status
            if resp.reason.as_ref().map_or(false, |r| {
                let contains_status = r.contains("status") || r.contains("query") || r.contains("check");
                crate::logger::log_debug(&format!("Checking reason '{}' for status keywords: {}", r, contains_status));
                contains_status
            }) {
                crate::logger::log_event("ROUTER", "Routing to QueryExecutor (status query detected)");
                RouteAction::QueryExecutor
            } else {
                match resp.action {
                    router::RouterAction::LaunchClaude => RouteAction::LaunchClaude,
                    router::RouterAction::CannotParse => {
                        // During active session, unclear commands might be status queries
                        let text_lower = text.to_lowercase();
                        if text_lower.contains("what") || text_lower.contains("status") || 
                           text_lower.contains("progress") || text_lower.contains("how") {
                            RouteAction::QueryExecutor
                        } else {
                            RouteAction::CannotParse
                        }
                    }
                    // Confirmation responses shouldn't appear in normal routing
                    _ => RouteAction::CannotParse
                }
            }
        } else {
            // No active session
            match resp.action {
                router::RouterAction::LaunchClaude => RouteAction::LaunchClaude,
                router::RouterAction::CannotParse => {
                    // First check if the reason indicates a status query
                    if resp.reason.as_ref().map_or(false, |r| {
                        let contains_status = r.contains("status") || r.contains("query") || r.contains("check");
                        crate::logger::log_debug(&format!("No active session - Checking reason '{}' for status keywords: {}", r, contains_status));
                        contains_status
                    }) {
                        crate::logger::log_event("ROUTER", "Routing to QueryExecutor (status query detected, will check for last session)");
                        RouteAction::QueryExecutor
                    } else {
                        // Also check the text directly for status-like queries
                        let text_lower = text.to_lowercase();
                        if text_lower.contains("what") && text_lower.contains("happening") ||
                           text_lower.contains("status") || 
                           text_lower.contains("last session") ||
                           text_lower.contains("previous session") ||
                           text_lower.contains("progress") {
                            RouteAction::QueryExecutor  // Will respond with last session info or "No active session"
                        } else {
                            RouteAction::CannotParse
                        }
                    }
                }
                // Confirmation responses shouldn't appear in normal routing
                _ => RouteAction::CannotParse
            }
        };
        
        Ok(RouteResponse {
            action,
            prompt: resp.prompt,
            reason: resp.reason,
            confidence: Some(resp.confidence),
        })
    }
}

/// Commands sent from core to app
pub enum AppCommand { 
    LaunchExecutor { prompt: String },
    QueryExecutorStatus { reply_tx: tokio::sync::oneshot::Sender<String> },
}

pub struct ExecutorAdapter { tx: Sender<AppCommand> }
impl ExecutorAdapter { pub fn new(tx: Sender<AppCommand>) -> Self { Self { tx } } }
#[async_trait]
impl ExecutorPort for ExecutorAdapter {
    async fn launch(&self, prompt: &str) -> Result<()> {
        self.tx.send(AppCommand::LaunchExecutor { prompt: prompt.to_string() }).await.map_err(|e| anyhow::anyhow!(e.to_string()))
    }
    
    async fn query_status(&self) -> Result<String> {
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        self.tx.send(AppCommand::QueryExecutorStatus { reply_tx }).await
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;
        reply_rx.await.map_err(|e| anyhow::anyhow!(e.to_string()))
    }
}

#[derive(Clone)]
pub struct OutboundChannel(pub mpsc::Sender<protocol::Message>);
#[async_trait]
impl OutboundPort for OutboundChannel {
    async fn send(&self, msg: protocol::Message) -> Result<()> {
            crate::logger::log_event("CORE_BRIDGE_OUT", &format!("Sending message: {:?}", msg));
            match self.0.try_send(msg) {
                Ok(()) => {
                    crate::logger::log_event("CORE_BRIDGE_OUT", "Message sent successfully");
                    Ok(())
                }
                Err(tokio::sync::mpsc::error::TrySendError::Full(m)) => {
                    crate::logger::log_event("CORE_BRIDGE_OUT", "Channel full, handling overflow");
                    // Drop noisy Status when channel is full; ensure important prompts are delivered
                    match &m {
                        protocol::Message::Status(_) => Ok(()),
                        _ => self.0.send(m).await.map_err(|e| anyhow::anyhow!(e.to_string())),
                    }
                }
                Err(tokio::sync::mpsc::error::TrySendError::Closed(m)) => {
                    crate::logger::log_event("CORE_BRIDGE_OUT", "Channel closed!");
                    // Channel closed; treat as non-fatal
                    let _ = m; // ignore
                    Ok(())
                }
            }
    }
}

pub struct CoreHandles {
    pub inbound_tx: mpsc::Sender<protocol::Message>,
    pub outbound_rx: mpsc::Receiver<protocol::Message>,
}

pub struct CoreSystem {
    pub handles: CoreHandles,
    pub core: std::sync::Arc<orchestrator_core::OrchestratorCore<RouterAdapter, ExecutorAdapter, OutboundChannel>>,
}

pub fn start_core_with_executor(exec: ExecutorAdapter) -> CoreSystem {
    let (in_tx, mut in_rx) = mpsc::channel::<protocol::Message>(100);
    let (out_tx, out_rx) = mpsc::channel::<protocol::Message>(100);

    let core = orchestrator_core::OrchestratorCore::new(
        RouterAdapter,
        exec,
        OutboundChannel(out_tx.clone()),
    );
    // Keep confirmation required; TUI will launch on confirm
    let core = std::sync::Arc::new(core);

    // Spawn processor loop
    let core_task = core.clone();
    tokio::spawn(async move {
        while let Some(msg) = in_rx.recv().await {
            crate::logger::log_event("CORE_TASK", &format!("Processing message: {:?}", msg));
            if let Err(e) = core_task.handle(msg).await {
                crate::logger::log_event("CORE_TASK", &format!("Error handling message: {}", e));
            }
        }
    });

    CoreSystem {
        handles: CoreHandles { inbound_tx: in_tx, outbound_rx: out_rx },
        core,
    }
}
