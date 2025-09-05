use orchestrator_core::OrchestratorCore;
use orchestrator_core::ports::{RouterPort, ExecutorPort, OutboundPort, RouteResponse, RouteAction};
use orchestrator_core::protocol;
use async_trait::async_trait;
use tokio::sync::mpsc;

struct TestRouter;

#[async_trait]
impl RouterPort for TestRouter {
    async fn route(&self, text: &str, _context: Option<orchestrator_core::ports::RouterContext>) -> anyhow::Result<RouteResponse> {
        if text.contains("Claude") || text.contains("snake") {
            Ok(RouteResponse {
                action: RouteAction::LaunchClaude,
                prompt: Some(text.to_string()),
                reason: None,
            })
        } else {
            Ok(RouteResponse {
                action: RouteAction::CannotParse,
                prompt: None,
                reason: Some("Cannot parse".to_string()),
            })
        }
    }
}

struct TestExecutor;

#[async_trait]
impl ExecutorPort for TestExecutor {
    async fn launch(&self, prompt: &str) -> anyhow::Result<()> {
        println!("TestExecutor: Would launch with prompt: {}", prompt);
        Ok(())
    }
    
    async fn query_status(&self) -> anyhow::Result<String> {
        Ok("No active session".to_string())
    }
}

struct TestOutbound {
    tx: mpsc::Sender<protocol::Message>,
}

#[async_trait]
impl OutboundPort for TestOutbound {
    async fn send(&self, msg: protocol::Message) -> anyhow::Result<()> {
        println!("Outbound message: {:?}", msg);
        self.tx.send(msg).await.map_err(|e| anyhow::anyhow!(e.to_string()))
    }
}

#[tokio::main]
async fn main() {
    println!("Testing core confirmation flow...\n");
    
    let (out_tx, mut out_rx) = mpsc::channel::<protocol::Message>(100);
    
    let core = OrchestratorCore::new(
        TestRouter,
        TestExecutor,
        TestOutbound { tx: out_tx },
    );
    
    // Test 1: Send a message that should trigger LaunchClaude
    println!("Test 1: Sending 'help me make a snake game with Claude'");
    let msg = protocol::Message::user_text(
        "help me make a snake game with Claude".to_string(),
        Some("test".to_string()),
        true
    );
    
    core.handle(msg).await.unwrap();
    
    // Check what was sent outbound
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    
    let mut got_confirmation = false;
    while let Ok(msg) = out_rx.try_recv() {
        match msg {
            protocol::Message::PromptConfirmation(pc) => {
                println!("✓ Got PromptConfirmation!");
                println!("  ID: {:?}", pc.id);
                println!("  Prompt: {}", pc.prompt);
                got_confirmation = true;
            }
            _ => {
                println!("  Other message: {:?}", msg);
            }
        }
    }
    
    if got_confirmation {
        println!("\n✅ Core correctly sends PromptConfirmation when require_confirmation is true");
    } else {
        println!("\n❌ ERROR: Core did NOT send PromptConfirmation!");
    }
}