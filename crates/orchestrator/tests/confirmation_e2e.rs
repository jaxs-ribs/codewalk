use orchestrator_core::{OrchestratorCore, ports::*, mocks::*};
use protocol::{Message, UserText};
use tokio::sync::mpsc;
use anyhow::Result;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

struct TestApp {
    core: Arc<OrchestratorCore<MockRouter, CountingExecutor, ChannelOutbound>>,
    tx: mpsc::Sender<Message>,
    rx: mpsc::Receiver<Message>,
    llm_call_count: Arc<AtomicU32>,
}

struct CountingExecutor {
    call_count: Arc<AtomicU32>,
}

#[async_trait::async_trait]
impl orchestrator_core::ports::ExecutorPort for CountingExecutor {
    async fn launch(&self, _prompt: &str) -> Result<()> {
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
        let (out_tx, rx) = mpsc::channel(10);
        let (tx, _) = mpsc::channel(10);
        let outbound = ChannelOutbound(out_tx);
        let core = Arc::new(OrchestratorCore::new(router, executor, outbound));
        
        Self {
            core,
            tx,
            rx,
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
    
    async fn send_confirmation(&self, accept: bool) {
        // Send as text through core, which will handle it as confirmation
        let response = if accept { "yes" } else { "no" };
        self.send_text(response).await;
    }
    
    async fn receive_message(&mut self) -> Message {
        self.rx.recv().await.expect("Should receive message")
    }
    
    fn llm_call_count(&self) -> u32 {
        self.llm_call_count.load(Ordering::SeqCst)
    }
}

#[tokio::test]
async fn test_voice_confirmation_flow() {
    let mut app = TestApp::new();
    
    // Trigger confirmation
    app.send_text("help me code").await;
    
    // Should receive prompt confirmation
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::PromptConfirmation(_)));
    
    // Voice confirm
    app.send_text("yes please").await;
    
    // Should receive status about launching
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Starting Claude Code"));
    }
    
    // Should have made only 1 LLM routing call (initial)
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test]
async fn test_confirmation_decline() {
    let mut app = TestApp::new();
    
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

#[tokio::test]
async fn test_confirmation_with_continue() {
    let mut app = TestApp::new();
    
    // Set active session to simulate having a previous session
    app.core.set_active_session("Claude".to_string());
    
    // Request to code
    app.send_text("refactor this").await;
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::PromptConfirmation(_)));
    
    // Say continue
    app.send_text("continue the previous session").await;
    
    // Should launch
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Starting Claude Code"));
    }
    
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test]
async fn test_confirmation_with_new() {
    let mut app = TestApp::new();
    
    // Request to code
    app.send_text("build a new feature").await;
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::PromptConfirmation(_)));
    
    // Say new
    app.send_text("start new session").await;
    
    // Should launch
    let msg = app.receive_message().await;
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Starting Claude Code"));
    }
    
    assert_eq!(app.llm_call_count(), 1);
}

#[tokio::test]
async fn test_no_duplicate_confirmations() {
    let mut app = TestApp::new();
    
    // Send coding request
    app.send_text("help me build an API").await;
    let msg1 = app.receive_message().await;
    assert!(matches!(msg1, Message::PromptConfirmation(_)));
    
    // Confirm
    app.send_text("yes").await;
    let msg2 = app.receive_message().await;
    assert!(matches!(msg2, Message::Status(_)));
    
    // Send another request - should get new confirmation, not reuse old one
    app.send_text("build another feature").await;
    let msg3 = app.receive_message().await;
    assert!(matches!(msg3, Message::PromptConfirmation(_)));
    
    // Ensure it's a new prompt
    if let Message::PromptConfirmation(pc1) = msg1 {
        if let Message::PromptConfirmation(pc3) = msg3 {
            assert_ne!(pc1.prompt, pc3.prompt);
            assert_ne!(pc1.id, pc3.id);
        }
    }
}