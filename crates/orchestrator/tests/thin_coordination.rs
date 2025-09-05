/// Test that the app coordination layer is thin and focused
use std::fs;
use std::path::Path;

#[test]
fn test_app_under_300_lines() {
    // Check the new app file size
    let app_path = Path::new("src/app_new.rs");
    if app_path.exists() {
        let content = fs::read_to_string(app_path).unwrap();
        let line_count = content.lines().count();
        
        assert!(
            line_count <= 300,
            "App coordination layer is too large: {} lines (should be < 300)",
            line_count
        );
        
        println!("App coordination layer: {} lines ✓", line_count);
    }
}

#[test]
fn test_no_ui_logic_in_app() {
    // Verify that app doesn't contain UI-specific logic
    let app_path = Path::new("src/app_new.rs");
    if app_path.exists() {
        let content = fs::read_to_string(app_path).unwrap();
        
        // Should not have direct ratatui rendering
        assert!(
            !content.contains("f.render_widget"),
            "App should not contain direct UI rendering"
        );
        
        // Should not manage scroll states directly
        assert!(
            !content.contains("scroll_position"),
            "App should not manage scroll states"
        );
        
        // Should delegate to TuiState
        assert!(
            content.contains("TuiState"),
            "App should use TuiState for UI management"
        );
    }
}

#[test]
fn test_no_business_logic_in_tui() {
    // Check that TUI crate doesn't import business logic
    let tui_cargo = Path::new("../orchestrator-tui/Cargo.toml");
    if tui_cargo.exists() {
        let content = fs::read_to_string(tui_cargo).unwrap();
        
        // Should not depend on the main orchestrator
        assert!(
            !content.contains("orchestrator ="),
            "TUI should not depend on main orchestrator"
        );
        
        // Should only depend on protocol for message types
        assert!(
            content.contains("protocol"),
            "TUI should depend on protocol for message types"
        );
    }
}

#[test]
fn test_clear_separation_of_concerns() {
    // Verify the crate structure
    assert!(Path::new("../orchestrator-core").exists(), "orchestrator-core should exist");
    assert!(Path::new("../orchestrator-adapters").exists(), "orchestrator-adapters should exist");
    assert!(Path::new("../orchestrator-tui").exists(), "orchestrator-tui should exist");
    
    // Each crate should have its own tests
    assert!(
        Path::new("../orchestrator-core/tests").exists(),
        "orchestrator-core should have tests"
    );
    assert!(
        Path::new("../orchestrator-tui/tests").exists(),
        "orchestrator-tui should have tests"
    );
}

#[test]
fn test_message_flow_architecture() {
    // Verify that the app uses message passing
    let app_path = Path::new("src/app_new.rs");
    if app_path.exists() {
        let content = fs::read_to_string(app_path).unwrap();
        
        // Should have message channels
        assert!(content.contains("mpsc::channel"), "App should use message channels");
        assert!(content.contains("core_in_tx"), "App should have core input channel");
        assert!(content.contains("core_out_rx"), "App should have core output channel");
        
        // Should handle messages
        assert!(
            content.contains("handle_core_message"),
            "App should handle core messages"
        );
        
        // Should use select! for concurrent handling
        assert!(
            content.contains("tokio::select!"),
            "App should use select! for concurrent message handling"
        );
    }
}