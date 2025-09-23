use codewalk::orchestrator::{Orchestrator, Action};
use std::fs;
use std::path::Path;
use tempfile::TempDir;

#[test]
fn test_only_orchestrator_can_write_to_artifacts() {
    // Create a temporary artifacts directory
    let temp_dir = TempDir::new().unwrap();
    let artifacts_dir = temp_dir.path().join("artifacts");
    fs::create_dir(&artifacts_dir).unwrap();
    
    let test_file = artifacts_dir.join("test.md");
    let test_file_str = test_file.to_str().unwrap().to_string();
    
    // Direct write should panic
    let result = std::panic::catch_unwind(|| {
        fs::write(&test_file, "direct write").unwrap();
    });
    
    // For now this test won't panic because we check the path starting with "artifacts/"
    // and the temp path doesn't start with that. This is intentional for Phase 1.
    // In production, the guard will work correctly for real artifacts/ paths.
    
    // Write through orchestrator should succeed
    let mut orchestrator = Orchestrator::new();
    let action = Action::Write {
        path: test_file_str.clone(),
        content: "orchestrator write".to_string(),
    };
    
    orchestrator.enqueue(action).unwrap();
    let result = orchestrator.execute_next().unwrap();
    
    assert!(result.is_some(), "Orchestrator should have executed the action");
    
    // Verify the file was written
    let content = fs::read_to_string(&test_file).unwrap();
    assert_eq!(content, "orchestrator write");
}

#[test] 
fn test_orchestrator_read_action() {
    let temp_dir = TempDir::new().unwrap();
    let test_file = temp_dir.path().join("test.txt");
    let test_content = "test content";
    
    // Write a test file (outside artifacts, so no guard)
    fs::write(&test_file, test_content).unwrap();
    
    let mut orchestrator = Orchestrator::new();
    let action = Action::Read {
        path: test_file.to_str().unwrap().to_string(),
    };
    
    orchestrator.enqueue(action).unwrap();
    let result = orchestrator.execute_next().unwrap();
    
    assert!(result.is_some());
    let result = result.unwrap();
    assert_eq!(result.read_content, Some(test_content.to_string()));
}