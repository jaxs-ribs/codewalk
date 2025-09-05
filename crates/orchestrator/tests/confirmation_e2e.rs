use orchestrator_core::{OrchestratorCore, mocks::*};
use protocol::{Message, UserText};
use tokio::sync::{mpsc, Mutex};
use anyhow::Result;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

struct TestApp {
    core: Arc<OrchestratorCore<MockRouter, CountingExecutor, TestOutbound>>,
    outbox: Arc<Mutex<Vec<Message>>>,
    llm_call_count: Arc<AtomicU32>,
}

struct CountingExecutor {
    call_count: Arc<AtomicU32>,
}

#[async_trait::async_trait]
impl orchestrator_core::ports::ExecutorPort for CountingExecutor {
    async fn launch(&self, _prompt: &str) -> Result<()> {
        eprintln!("DEBUG test: CountingExecutor.launch called");
        self.call_count.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
    
    async fn query_status(&self) -> Result<String> {
        Ok("Claude Code is running".to_string())
    }
}

impl TestApp {
    fn new() -> Self {
        let router = MockRouter;
        let call_count = Arc::new(AtomicU32::new(0));
        let executor = CountingExecutor { call_count: call_count.clone() };
        let (out_tx, _rx_tok) = mpsc::channel(10);
        let outbox = Arc::new(Mutex::new(Vec::new()));
        let outbound = TestOutbound { tok_tx: out_tx, outbox: outbox.clone() };
        let core = Arc::new(OrchestratorCore::new(router, executor, outbound));
        
        Self {
            core,
            outbox,
            llm_call_count: call_count,
        }
    }
    
    async fn send_text(&self, text: &str) {
        self.core.handle(Message::UserText(UserText {
            v: Some(protocol::VERSION),
            id: None,
            source: Some("test".to_string()),
            text: text.to_string(),
            final_: true,
        })).await.unwrap();
    }
    
    // removed unused send_confirmation helper
    
    async fn receive_message(&self) -> Message {
        // Poll the shared outbox with a short timeout
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        loop {
            let mut guard = self.outbox.lock().await;
            if let Some(msg) = guard.pop() {
                return msg;
            }
            if std::time::Instant::now() >= deadline { panic!("Timed out waiting for message"); }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
    }
    
    fn llm_call_count(&self) -> u32 {
        self.llm_call_count.load(Ordering::SeqCst)
    }
}

// Local outbound that avoids cross-crate channel quirks
struct TestOutbound {
    tok_tx: mpsc::Sender<Message>,
    outbox: Arc<Mutex<Vec<Message>>>,
}

#[async_trait::async_trait]
impl orchestrator_core::ports::OutboundPort for TestOutbound {
    async fn send(&self, msg: Message) -> Result<()> {
        // Best-effort: send to async channel and record in outbox
        let _ = self.tok_tx.try_send(msg.clone());
        self.outbox.lock().await.push(msg);
        Ok(())
    }
}

#[tokio::test(flavor = "current_thread")]
async fn test_voice_confirmation_flow() {
    let app = TestApp::new();
    
    // Trigger confirmation
    app.send_text("help me code").await;
    
    // Voice confirm
    app.send_text("yes please").await;
    // Allow core to process
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    
    // Should have made only 1 LLM routing call (initial)
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn test_confirmation_decline() {
    let app = TestApp::new();
    
    // Trigger confirmation
    app.send_text("build something").await;
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::PromptConfirmation(_)));
    
    // Decline
    app.send_text("no thanks").await;
    
    // Should receive cancellation status
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("canceled"));
    }
    
    // Should not have launched executor
    assert_eq!(app.llm_call_count(), 0);
}

#[tokio::test(flavor = "current_thread")]
async fn test_confirmation_with_continue() {
    let app = TestApp::new();
    
    // Set active session to simulate having a previous session
    app.core.set_active_session("Claude".to_string());
    
    // Request to code then confirm via text
    app.send_text("refactor this").await;
    app.send_text("continue the previous session").await;
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn test_confirmation_with_new() {
    let app = TestApp::new();
    
    // Request to code then confirm via text
    app.send_text("build a new feature").await;
    app.send_text("start new session").await;
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn test_no_duplicate_confirmations() {
    let mut app = TestApp::new();
    
    // Send coding request and confirm
    app.send_text("help me build an API").await;
    app.send_text("yes").await;
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    // Send another request and confirm
    app.send_text("build another feature").await;
    app.send_text("yes").await;
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    // Should have launched twice
    assert_eq!(app.llm_call_count(), 2);
}
