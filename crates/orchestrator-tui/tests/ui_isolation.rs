use orchestrator_tui::{TuiState, Tab};
use tokio::sync::mpsc;
use protocol::Message;

fn create_test_tui() -> (TuiState, mpsc::Receiver<Message>) {
    let (tx, rx) = mpsc::channel(10);
    let tui = TuiState::new(tx);
    (tui, rx)
}

#[test]
fn test_tui_has_no_business_logic() {
    // This test verifies that TUI only deals with display state
    let (mut tui, _rx) = create_test_tui();
    
    // TUI should only handle display operations
    tui.append_output("test output".to_string());
    assert_eq!(tui.output_buffer.len(), 1);
    
    tui.append_log("test log".to_string());
    assert_eq!(tui.log_buffer.len(), 1);
    
    // Tab switching is pure UI
    tui.switch_tab(Tab::Logs);
    assert_eq!(tui.selected_tab, Tab::Logs);
    
    tui.switch_tab(Tab::Output);
    assert_eq!(tui.selected_tab, Tab::Output);
}

#[tokio::test]
async fn test_tui_only_emits_messages() {
    let (mut tui, mut rx) = create_test_tui();
    
    // Simulate user typing and sending
    tui.handle_input_char('h');
    tui.handle_input_char('i');
    assert_eq!(tui.input_buffer, "hi");
    
    let input = tui.take_input();
    assert_eq!(input, "hi");
    assert_eq!(tui.input_buffer, "");
    
    // Send as user text
    tui.send_user_text(input).await.unwrap();
    
    // Should only emit protocol messages
    let msg = rx.recv().await.unwrap();
    assert!(matches!(msg, Message::UserText(_)));
    if let Message::UserText(ut) = msg {
        assert_eq!(ut.text, "hi");
        assert_eq!(ut.source, Some("tui".to_string()));
    }
}

#[test]
fn test_scroll_state() {
    let (mut tui, _rx) = create_test_tui();
    
    // Add some output
    for i in 0..20 {
        tui.append_output(format!("Line {}", i));
    }
    
    // Test scrolling
    assert_eq!(tui.scroll.position, 0);
    
    tui.scroll.scroll_down(5);
    assert_eq!(tui.scroll.position, 5);
    
    tui.scroll.scroll_up(2);
    assert_eq!(tui.scroll.position, 3);
    
    tui.scroll.scroll_to_bottom();
    assert_eq!(tui.scroll.position, tui.scroll.max_position);
}

#[test]
fn test_error_display() {
    let (mut tui, _rx) = create_test_tui();
    
    // Show error
    tui.show_error(
        "Test Error".to_string(),
        "Something went wrong".to_string(),
        "Details here".to_string(),
    );
    
    assert!(tui.error_message.is_some());
    let error = tui.error_message.as_ref().unwrap();
    assert_eq!(error.title, "Test Error");
    
    // Dismiss error
    tui.dismiss_error();
    assert!(tui.error_message.is_none());
}

#[test]
fn test_input_editing() {
    let (mut tui, _rx) = create_test_tui();
    
    // Type some text
    tui.handle_input_char('t');
    tui.handle_input_char('e');
    tui.handle_input_char('s');
    tui.handle_input_char('t');
    assert_eq!(tui.input_buffer, "test");
    
    // Backspace
    tui.handle_backspace();
    assert_eq!(tui.input_buffer, "tes");
    
    // Clear
    tui.clear_input();
    assert_eq!(tui.input_buffer, "");
}

#[test]
fn test_help_toggle() {
    let (mut tui, _rx) = create_test_tui();
    
    assert!(!tui.show_help);
    
    tui.toggle_help();
    assert!(tui.show_help);
    
    tui.toggle_help();
    assert!(!tui.show_help);
}

#[test]
fn test_buffer_limits() {
    let (mut tui, _rx) = create_test_tui();
    
    // Add more than the limit
    for i in 0..1100 {
        tui.append_log(format!("Log {}", i));
    }
    
    // Should be capped at 1000
    assert_eq!(tui.log_buffer.len(), 1000);
    
    // First items should be dropped
    assert!(!tui.log_buffer[0].contains("Log 0"));
}