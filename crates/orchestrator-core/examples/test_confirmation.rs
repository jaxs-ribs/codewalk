use orchestrator_core::OrchestratorCore;
use orchestrator_core::ports::{RouterPort, ExecutorPort, OutboundPort, RouteResponse, RouteAction};
use protocol;
use async_trait::async_trait;
use tokio::sync::mpsc;

struct TestRouter;

#[async_trait]
impl RouterPort for TestRouter {
    async fn route(&self, text: &str, _context: Option<orchestrator_core::ports::RouterContext>) -> anyhow::Result<RouteResponse> {
        println!("TestRouter: routing '{}'", text);
        if text.contains("Claude") || text.contains("snake") {
            println!("TestRouter: returning LaunchClaude");
            Ok(RouteResponse {
                action: RouteAction::LaunchClaude,
                prompt: Some(text.to_string()),
                reason: None,
                confidence: Some(0.9),
            })
        } else {
            Ok(RouteResponse {
                action: RouteAction::CannotParse,
                prompt: None,
                reason: Some("Cannot parse".to_string()),
                confidence: Some(0.5),
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
        println!("TestOutbound: Sending message: {:?}", msg);
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
    
    println!("Core created with require_confirmation = true (default)\n");
    
    // Test 1: Send a message that should trigger LaunchClaude
    println!("Test 1: Sending 'help me make a snake game with Claude'");
    let msg = protocol::Message::user_text(
        "help me make a snake game with Claude".to_string(),
        Some("test".to_string()),
        true
    );
    
    println!("Calling core.handle()...");
    core.handle(msg).await.unwrap();
    
    // Check what was sent outbound
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    
    println!("\nChecking outbound messages...");
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
        println!("\n✅ SUCCESS: Core correctly sends PromptConfirmation when require_confirmation is true");
    } else {
        println!("\n❌ ERROR: Core did NOT send PromptConfirmation!");
        println!("This means the outbound channel is not working properly.");
    }
}