use orchestrator_core::{OrchestratorCore, mocks::*};
use protocol::{Message, UserText};
use tokio::sync::mpsc;

async fn create_test_core() -> (OrchestratorCore<MockRouter, MockExecutor, ChannelOutbound>, mpsc::Receiver<Message>) {
    let router = MockRouter;
    let executor = MockExecutor;
    let (tx, rx) = mpsc::channel(10);
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    (core, rx)
}

#[tokio::test]
async fn test_routing_through_core_only() {
    let (core, mut rx) = create_test_core().await;
    
    // Send user text
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "build me a web app".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive prompt confirmation
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::PromptConfirmation(_)));
    if let Message::PromptConfirmation(pc) = msg {
        assert_eq!(pc.prompt, "build me a web app");
        assert_eq!(pc.executor, "Claude");
    }
}

#[tokio::test]
async fn test_status_query_routing() {
    let (core, mut rx) = create_test_core().await;
    
    // Set active session
    core.set_active_session("Claude".to_string());
    
    // Send status query
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "what's the status?".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive status message
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Mock executor status"));
    }
}

#[tokio::test]
async fn test_cannot_parse_routing() {
    let (core, mut rx) = create_test_core().await;
    
    // Send unclear text
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "hello there".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive status with cannot parse reason
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.to_lowercase().contains("non-coding") || 
                status.text.to_lowercase().contains("unclear"));
    }
}

#[tokio::test]
async fn test_confirmation_not_required() {
    let (mut core, mut rx) = create_test_core().await;
    core.set_require_confirmation(false);
    
    // Send coding request
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "refactor my code".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive status about starting immediately
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::Status(_)));
    if let Message::Status(status) = msg {
        assert!(status.text.contains("Starting Claude Code"));
    }
}

#[tokio::test]
async fn test_empty_text_ignored() {
    let (core, mut rx) = create_test_core().await;
    
    // Send empty text
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "  ".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should not receive any message
    let result = rx.try_recv();
    assert!(result.is_err());
}

#[tokio::test]
async fn test_multiple_routing_requests() {
    let (core, mut rx) = create_test_core().await;
    
    // Send request -> get confirmation -> decline -> repeat
    for i in 0..3 {
        // Send request
        core.handle(Message::UserText(UserText {
            v: Some(protocol::VERSION),
            id: None,
            source: Some("test".to_string()),
            text: format!("build feature {}", i),
            final_: true,
        })).await.unwrap();
        
        // Should receive prompt confirmation
        let msg = rx.recv().await.unwrap();
        assert!(matches!(msg, Message::PromptConfirmation(_)));
        if let Message::PromptConfirmation(pc) = msg {
            assert!(pc.prompt.contains(&format!("feature {}", i)));
        }
        
        // Decline to clear pending confirmation
        core.handle(Message::UserText(UserText {
            v: Some(protocol::VERSION),
            id: None,
            source: Some("test".to_string()),
            text: "no".to_string(),
            final_: true,
        })).await.unwrap();
        
        // Should receive cancellation status
        let msg = rx.recv().await.unwrap();
        assert!(matches!(msg, Message::Status(_)));
    }
}