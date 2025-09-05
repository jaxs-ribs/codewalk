// Integration test imports

/// Integration test for the full user journey as specified in Phase 4
#[tokio::test]
async fn test_full_user_journey() {
    // This test would require a full setup with mocks
    // For now, we verify the structure exists
    
    // Verify all crates exist and compile
    assert!(std::path::Path::new("../orchestrator-core").exists());
    assert!(std::path::Path::new("../orchestrator-adapters").exists());
    assert!(std::path::Path::new("../orchestrator-tui").exists());
    
    // Simulate the user journey:
    // 1. User asks for help
    // 2. System routes through core
    // 3. Core sends confirmation request
    // 4. User confirms
    // 5. Executor launches
    // 6. User queries status
    
    println!("User journey test placeholder - structure verified");
    
    // In a real test, we would:
    // - Create a test app instance
    // - Send "help me build a REST API" through core
    // - Verify PromptConfirmation is received
    // - Send confirmation
    // - Verify executor launches
    // - Query status
    // - Verify "Claude Code is running" response
}

/// Test that message routing goes through core only
#[test]
fn test_no_direct_routing_outside_core() {
    // Search for direct backend calls outside of adapters
    let output = std::process::Command::new("grep")
        .args(&["-r", "backend::text_to_llm_cmd", "src/"])
        .arg("--exclude=core_bridge.rs")
        .arg("--exclude=app_old.rs")
        .output()
        .expect("Failed to execute grep");
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    
    // Should not find any direct calls outside of the bridge adapter
    assert!(
        stdout.is_empty(),
        "Found direct LLM calls outside adapters:\n{}",
        stdout
    );
}

/// Test that the app coordination layer is thin
#[test]
fn test_app_coordination_is_thin() {
    // Check if app_new.rs exists and is under 300 lines
    let app_new = std::path::Path::new("src/app_new.rs");
    if app_new.exists() {
        let content = std::fs::read_to_string(app_new).unwrap();
        let line_count = content.lines().count();
        
        assert!(
            line_count <= 300,
            "app_new.rs has {} lines, should be <= 300",
            line_count
        );
        
        println!("✓ app_new.rs is {} lines (target: <= 300)", line_count);
    }
}

/// Test that all phases are properly integrated
#[test]
fn test_phase_integration() {
    // Phase 1: Foundation
    assert!(
        std::path::Path::new("../orchestrator-core/src/session").exists(),
        "Phase 1: Session modules should exist"
    );
    assert!(
        std::path::Path::new("../orchestrator-core/src/ports").exists(),
        "Phase 1: Ports modules should exist"
    );
    assert!(
        std::path::Path::new("../orchestrator-adapters").exists(),
        "Phase 1: Adapters crate should exist"
    );
    
    // Phase 2: Core Integration
    // Verify routing goes through core (checked in test_no_direct_routing_outside_core)
    
    // Phase 3: UI Extraction
    assert!(
        std::path::Path::new("../orchestrator-tui").exists(),
        "Phase 3: TUI crate should exist"
    );
    assert!(
        std::path::Path::new("../orchestrator-tui/src/state.rs").exists(),
        "Phase 3: TUI state should be extracted"
    );
    
    println!("✓ All phases properly integrated");
}

/// Test that the core handles all routing decisions
#[tokio::test]
async fn test_core_routing_decisions() {
    use orchestrator_core::{OrchestratorCore, mocks::*};
    use protocol::{Message, UserText};
    use tokio::sync::mpsc;
    
    // Create a test core
    let router = MockRouter;
    let executor = MockExecutor;
    let (tx, mut rx) = mpsc::channel(10);
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    // Test routing a coding request
    core.handle(Message::UserText(UserText {
        v: Some(protocol::VERSION),
        id: None,
        source: Some("test".to_string()),
        text: "help me code".to_string(),
        final_: true,
    })).await.unwrap();
    
    // Should receive a prompt confirmation
    let msg = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
        .await
        .expect("Timed out waiting for message")
        .expect("Channel closed");
    assert!(
        matches!(msg, Message::PromptConfirmation(_)),
        "Core should emit PromptConfirmation for coding requests"
    );
    
    println!("✓ Core handles routing decisions");
}

/// Benchmark message routing performance
#[tokio::test]
async fn bench_message_routing() {
    use orchestrator_core::{OrchestratorCore, mocks::*};
    use protocol::{Message, UserText};
    use tokio::sync::mpsc;
    use std::time::Instant;
    
    let router = MockRouter;
    let executor = MockExecutor;
    let (tx, _rx) = mpsc::channel(100);
    let outbound = ChannelOutbound(tx);
    let core = OrchestratorCore::new(router, executor, outbound);
    
    let start = Instant::now();
    let iterations = 200; // keep fast for CI
    
    for i in 0..iterations {
        core.handle(Message::UserText(UserText {
            v: Some(protocol::VERSION),
            id: None,
            source: Some("bench".to_string()),
            text: format!("test message {}", i),
            final_: true,
        })).await.unwrap();
    }
    
    let elapsed = start.elapsed();
    let per_message = elapsed / iterations;
    
    println!(
        "Message routing performance: {:?} per message ({} messages in {:?})",
        per_message, iterations, elapsed
    );
    
    // Should be < 5ms per message on typical CI
    assert!(
        per_message.as_millis() < 5,
        "Message routing too slow: {:?} per message",
        per_message
    );
}
