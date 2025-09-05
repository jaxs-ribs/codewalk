use orchestrator_core::{OrchestratorCore, ports::{RouterPort, ExecutorPort, OutboundPort, RouterContext, RouteResponse, RouteAction}, mocks::*};
use protocol::{Message, UserText, ConfirmResponse};
use tokio::sync::mpsc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

/// Test the complete flow from user input to executor launch
#[tokio::test]
async fn test_complete_user_flow() {
    // Setup
    let (tx, mut rx) = mpsc::channel(10);
    let launched = Arc::new(AtomicBool::new(false));
    let launched_clone = launched.clone();
    
    // Create a custom executor that tracks launches
    struct TrackingExecutor {
        launched: Arc<AtomicBool>,
    }
    
    #[async_trait::async_trait]
    impl ExecutorPort for TrackingExecutor {
        async fn launch(&self, _prompt: &str) -> anyhow::Result<()> {
            self.launched.store(true, Ordering::SeqCst);
            Ok(())
        }
        
        async fn query_status(&self) -> anyhow::Result<String> {
            if self.launched.load(Ordering::SeqCst) {
                Ok("Claude Code is running".to_string())
            } else {
                Ok("No active session".to_string())
            }
        }
    }
    
    let router = MockRouter;
    let executor = TrackingExecutor { launched: launched_clone };
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    // Step 1: User sends coding request
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "help me build a REST API".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Step 2: Should receive confirmation prompt
    let msg = rx.recv().await.unwrap();
    let confirmation_id = if let Message::PromptConfirmation(pc) = msg {
        assert_eq!(pc.prompt, "help me build a REST API");
        assert_eq!(pc.executor, "Claude");
        pc.id
    } else {
        panic!("Expected PromptConfirmation, got {:?}", msg);
    };
    
    // Step 3: User confirms
    core.handle(Message::ConfirmResponse(ConfirmResponse {
        v: Some(protocol::VERSION),
        id: confirmation_id.clone(),
        for_: "executor_launch".to_string(),
        accept: true,
    })).await.unwrap();
    
    // Step 4: Should receive launch status
    let msg = rx.recv().await.unwrap();
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Starting Claude Code"));
    } else {
        panic!("Expected Status message, got {:?}", msg);
    }
    
    // Step 5: Verify executor was launched
    assert!(launched.load(Ordering::SeqCst), "Executor should have been launched");
    
    // Set active session so status queries work
    core.set_active_session("Claude".to_string());
    
    // Step 6: Query status
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "what's the status?".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Step 7: Should receive status response
    let msg = rx.recv().await.unwrap();
    if let Message::Status(status) = msg {
        assert_eq!(status.text, "Claude Code is running");
    } else {
        panic!("Expected Status with running message, got {:?}", msg);
    }
}

/// Test that declined confirmations don't launch
#[tokio::test]
async fn test_declined_confirmation() {
    let (tx, mut rx) = mpsc::channel(10);
    let launched = Arc::new(AtomicBool::new(false));
    let launched_clone = launched.clone();
    
    struct NoLaunchExecutor {
        launched: Arc<AtomicBool>,
    }
    
    #[async_trait::async_trait]
    impl ExecutorPort for NoLaunchExecutor {
        async fn launch(&self, _prompt: &str) -> anyhow::Result<()> {
            self.launched.store(true, Ordering::SeqCst);
            Ok(())
        }
        
        async fn query_status(&self) -> anyhow::Result<String> {
            Ok("No active session".to_string())
        }
    }
    
    let router = MockRouter;
    let executor = NoLaunchExecutor { launched: launched_clone };
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    // Send coding request
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "refactor my code".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Get confirmation
    let msg = rx.recv().await.unwrap();
    let confirmation_id = if let Message::PromptConfirmation(pc) = msg {
        pc.id
    } else {
        panic!("Expected PromptConfirmation");
    };
    
    // Decline
    core.handle(Message::ConfirmResponse(ConfirmResponse {
        v: Some(protocol::VERSION),
        id: confirmation_id,
        for_: "executor_launch".to_string(),
        accept: false,
    })).await.unwrap();
    
    // Should receive cancellation status
    let msg = rx.recv().await.unwrap();
    if let Message::Status(status) = msg {
        assert!(status.text.contains("canceled"));
    } else {
        panic!("Expected cancellation Status");
    }
    
    // Verify executor was NOT launched
    assert!(!launched.load(Ordering::SeqCst), "Executor should NOT have been launched");
}

/// Test that confirmation state is properly managed
#[tokio::test]
async fn test_confirmation_state_management() {
    let (tx, mut rx) = mpsc::channel(10);
    let router = MockRouter;
    let executor = MockExecutor;
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    // Send first request
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "build feature A".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Get first confirmation
    let msg1 = rx.recv().await.unwrap();
    let id1 = if let Message::PromptConfirmation(pc) = msg1 {
        pc.id.unwrap()
    } else {
        panic!("Expected PromptConfirmation");
    };
    
    // While confirmation is pending, send another text
    // This should be treated as a confirmation response
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "yes".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive launch status
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::Status(_)));
    
    // Now send a new request - should get new confirmation
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "build feature B".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should get new confirmation with different ID
    let msg2 = rx.recv().await.unwrap();
    if let Message::PromptConfirmation(pc) = msg2 {
        assert_ne!(pc.id.unwrap(), id1, "Should have different confirmation ID");
        assert!(pc.prompt.contains("feature B"));
    } else {
        panic!("Expected new PromptConfirmation");
    }
}

/// Test error handling
#[tokio::test]
async fn test_error_handling() {
    struct ErrorRouter;
    
    #[async_trait::async_trait]
    impl RouterPort for ErrorRouter {
        async fn route(&self, _text: &str, _context: Option<RouterContext>) -> anyhow::Result<RouteResponse> {
            Err(anyhow::anyhow!("Router error"))
        }
    }
    
    let (tx, mut rx) = mpsc::channel(10);
    let router = ErrorRouter;
    let executor = MockExecutor;
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    // Send request that will fail routing
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "test".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive error status
    let msg = rx.recv().await.unwrap();
    if let Message::Status(status) = msg {
        assert_eq!(status.level, "error");
        assert!(status.text.contains("router error"));
    } else {
        panic!("Expected error Status");
    }
}

/// Test concurrent message handling
#[tokio::test]
#[ignore] // Has timing issues, run manually with --ignored
async fn test_concurrent_messages() {
    let (tx, mut rx) = mpsc::channel(100);
    let router = MockRouter;
    let executor = MockExecutor;
    let outbound = ChannelOutbound(tx);
    let core = Arc::new(OrchestratorCore::new(router, executor, outbound));
    
    // Send multiple messages concurrently
    let mut handles = vec![];
    for i in 0..10 {
        let core_clone = core.clone();
        let handle = tokio::spawn(async move {
            core_clone.handle(Message::UserText(UserText {
                v: Some(protocol::VERSION),
                id: None,
                source: Some("concurrent".to_string()),
                text: format!("request {}", i),
                final_: true,
            })).await
        });
        handles.push(handle);
    }
    
    // Wait for all to complete
    for handle in handles {
        handle.await.unwrap().unwrap();
    }
    
    // Should have received responses for all
    let mut count = 0;
    while let Ok(_msg) = rx.try_recv() {
        count += 1;
    }
    assert!(count >= 10, "Should have received at least 10 messages, got {}", count);
}