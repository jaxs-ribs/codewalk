pub mod ports;
pub mod session;

use anyhow::Result;
use ports::{ExecutorPort, OutboundPort, RouteAction, RouterPort};

/// Headless orchestrator core: consumes protocol messages, emits protocol messages.
pub struct OrchestratorCore<R: RouterPort, E: ExecutorPort, O: OutboundPort> {
    router: R,
    executor: E,
    outbound: O,
    require_confirmation: bool,
    pending_confirmation: std::sync::Mutex<Option<PendingConfirmation>>,
    active_session: std::sync::Mutex<Option<ports::RouterContext>>,
}

struct PendingConfirmation {
    id: String,
    prompt: String,
}

impl<R: RouterPort, E: ExecutorPort, O: OutboundPort> OrchestratorCore<R, E, O> {
    pub fn new(router: R, executor: E, outbound: O) -> Self {
        Self { router, executor, outbound, require_confirmation: true, pending_confirmation: std::sync::Mutex::new(None), active_session: std::sync::Mutex::new(None) }
    }

    pub fn set_require_confirmation(&mut self, yes: bool) { self.require_confirmation = yes; }
    
    /// Set active session context (call when executor starts)
    pub fn set_active_session(&self, session_type: String) {
        *self.active_session.lock().unwrap() = Some(ports::RouterContext {
            has_active_session: true,
            session_type: Some(session_type),
        });
    }
    
    /// Clear active session context (call when executor ends)
    pub fn clear_active_session(&self) {
        *self.active_session.lock().unwrap() = None;
    }

    /// Entry point for inbound messages (Phase 2: handle user_text only)
    pub async fn handle(&self, msg: protocol::Message) -> Result<()> {
        match msg {
            protocol::Message::UserText(ut) => self.handle_user_text(ut).await,
            protocol::Message::Ack(_) => Ok(()), // ignore inbound acks
            protocol::Message::Status(_) => Ok(()),
            protocol::Message::PromptConfirmation(_) => Ok(()),
            protocol::Message::ConfirmResponse(cr) => self.handle_confirm(cr).await,
        }
    }

    async fn handle_user_text(&self, ut: protocol::UserText) -> Result<()> {
        // Simplified: treat every message as final; ignore id/partial.
        let text_trim = ut.text.trim();
        if text_trim.is_empty() { return Ok(()); }

        // Get current session context for router (drop lock before await)
        let context = {
            self.active_session.lock().unwrap().clone()
        };
        
        // Route the text (send error status on failure)
        let decision = match self.router.route(text_trim, context).await {
            Ok(d) => d,
            Err(e) => {
                let _ = self.outbound.send(protocol::Message::Status(protocol::Status{
                    v: Some(protocol::VERSION), level: "error".into(), text: format!("router error: {}", e)
                })).await;
                return Ok(());
            }
        };
        match decision.action {
            RouteAction::CannotParse => {
                let reason = decision.reason.unwrap_or_else(|| "could not understand".to_string());
                self.outbound.send(protocol::Message::Status(protocol::Status {
                    v: Some(protocol::VERSION),
                    level: "info".to_string(),
                    text: reason,
                })).await
            }
            RouteAction::QueryExecutor => {
                // Always query the executor - it handles both active and past sessions
                match self.executor.query_status().await {
                    Ok(summary) => {
                        // Send the summary as status message
                        self.outbound.send(protocol::Message::Status(protocol::Status {
                            v: Some(protocol::VERSION),
                            level: "info".to_string(),
                            text: summary,
                        })).await?;
                    }
                    Err(e) => {
                        // Check if there's an active session for better error message
                        let session_info = self.active_session.lock().unwrap().clone();
                        let msg = if let Some(ctx) = session_info {
                            format!("Active {} session is running but couldn't fetch details: {}", 
                                    ctx.session_type.as_deref().unwrap_or("executor"), e)
                        } else {
                            format!("Couldn't fetch session information: {}", e)
                        };
                        self.outbound.send(protocol::Message::Status(protocol::Status {
                            v: Some(protocol::VERSION),
                            level: "info".to_string(),
                            text: msg,
                        })).await?;
                    }
                }
                Ok(())
            }
            RouteAction::LaunchClaude => {
                let prompt = decision.prompt.unwrap_or_else(|| text_trim.to_string());
                if self.require_confirmation {
                    // Generate unique confirmation ID
                    let confirmation_id = format!("confirm_{}", std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis());
                    
                    // Store pending confirmation
                    *self.pending_confirmation.lock().unwrap() = Some(PendingConfirmation {
                        id: confirmation_id.clone(),
                        prompt: prompt.clone(),
                    });
                    
                    self.outbound.send(protocol::Message::PromptConfirmation(protocol::PromptConfirmation {
                        v: Some(protocol::VERSION),
                        id: Some(confirmation_id),
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
                        text: format!("Starting Claude Code for: {}", prompt),
                    })).await
                }
            }
        }
    }

    async fn handle_confirm(&self, cr: protocol::ConfirmResponse) -> Result<()> {
        if cr.for_ != "executor_launch" { return Ok(()); }
        
        let pending = {
            let mut guard = self.pending_confirmation.lock().unwrap();
            // Only process if the confirmation ID matches (or no ID for backward compat)
            if let Some(ref pending) = *guard {
                if cr.id.is_none() || cr.id.as_ref() == Some(&pending.id) {
                    guard.take()
                } else {
                    // Confirmation ID doesn't match - ignore
                    return Ok(());
                }
            } else {
                None
            }
        };
        
        if cr.accept {
            if let Some(pending) = pending {
                self.executor.launch(&pending.prompt).await?;
                self.outbound.send(protocol::Message::Status(protocol::Status{
                    v: Some(protocol::VERSION), level: "info".into(), text: format!("Starting Claude Code for: {}", pending.prompt)
                })).await?;
            }
        } else {
            // canceled: emit status
            self.outbound.send(protocol::Message::Status(protocol::Status{
                v: Some(protocol::VERSION), level: "info".into(), text: "executor launch canceled".into()
            })).await?;
        }
        Ok(())
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
        async fn route(&self, text: &str, context: Option<ports::RouterContext>) -> Result<ports::RouteResponse> {
            let text_l = text.to_lowercase();
            
            // Check for status queries when session is active
            if let Some(ctx) = context {
                if ctx.has_active_session {
                    if text_l.contains("what") && text_l.contains("happening") ||
                       text_l.contains("status") || text_l.contains("summary") ||
                       text_l.contains("progress") || text_l.contains("update") {
                        return Ok(ports::RouteResponse {
                            action: ports::RouteAction::QueryExecutor,
                            prompt: None,
                            reason: None,
                            confidence: Some(0.9),
                        });
                    }
                }
            }
            
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
        async fn query_status(&self) -> Result<String> { Ok("Mock executor status".to_string()) }
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
