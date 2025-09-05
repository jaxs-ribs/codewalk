use orchestrator_core::session::{SessionState, SessionStateMachine, SessionContext, SessionHistory, SessionEventType};

struct TestCore {
    state_machine: SessionStateMachine,
    context: SessionContext,
    history: SessionHistory,
}

impl TestCore {
    fn new() -> Self {
        Self {
            state_machine: SessionStateMachine::new(),
            context: SessionContext::new(),
            history: SessionHistory::new(100),
        }
    }

    fn session_state(&self) -> SessionState {
        self.state_machine.current_state()
    }

    async fn start_session(&mut self, prompt: &str) {
        self.state_machine.start().unwrap();
        self.context.set_active_prompt(prompt.to_string());
        self.history.add_event(SessionEventType::Started, None);
    }

    async fn complete_session(&mut self) {
        self.state_machine.complete().unwrap();
        self.context.clear_active_prompt();
        self.history.add_event(SessionEventType::Completed, None);
    }
}

#[tokio::test]
async fn test_session_state_transitions() {
    let mut core = TestCore::new();
    
    assert_eq!(core.session_state(), SessionState::Idle);
    
    core.start_session("test prompt").await;
    assert_eq!(core.session_state(), SessionState::Running);
    
    core.complete_session().await;
    assert_eq!(core.session_state(), SessionState::Completed);
}

#[tokio::test]
async fn test_invalid_state_transitions() {
    let mut state_machine = SessionStateMachine::new();
    
    assert_eq!(state_machine.current_state(), SessionState::Idle);
    
    let result = state_machine.transition_to(SessionState::Completed);
    assert!(result.is_err());
    
    state_machine.start().unwrap();
    assert_eq!(state_machine.current_state(), SessionState::Running);
    
    let result = state_machine.transition_to(SessionState::Idle);
    assert!(result.is_err());
}

#[tokio::test]
async fn test_session_pause_resume() {
    let mut state_machine = SessionStateMachine::new();
    
    state_machine.start().unwrap();
    assert_eq!(state_machine.current_state(), SessionState::Running);
    
    state_machine.pause().unwrap();
    assert_eq!(state_machine.current_state(), SessionState::Paused);
    
    state_machine.resume().unwrap();
    assert_eq!(state_machine.current_state(), SessionState::Running);
}

#[tokio::test]
async fn test_session_context() {
    let mut context = SessionContext::new()
        .with_user_id("test_user".to_string())
        .with_project_path("/test/path".to_string());
    
    assert_eq!(context.user_id, Some("test_user".to_string()));
    assert_eq!(context.project_path, Some("/test/path".to_string()));
    
    context.set_active_prompt("build me an app".to_string());
    assert_eq!(context.active_prompt, Some("build me an app".to_string()));
    
    context.set_metadata("test_key".to_string(), serde_json::json!("test_value"));
    assert_eq!(context.get_metadata("test_key").unwrap(), &serde_json::json!("test_value"));
}

#[tokio::test]
async fn test_session_history() {
    let mut history = SessionHistory::new(10);
    
    assert!(history.is_empty());
    
    history.add_event(SessionEventType::Started, None);
    history.add_event(SessionEventType::UserInput("hello".to_string()), None);
    history.add_event(SessionEventType::SystemResponse("hi there".to_string()), None);
    
    assert_eq!(history.len(), 3);
    
    let last_input = history.get_last_user_input();
    assert_eq!(last_input, Some("hello".to_string()));
    
    let conversation = history.get_conversation_history();
    assert_eq!(conversation.len(), 2);
    assert_eq!(conversation[0], ("hello".to_string(), true));
    assert_eq!(conversation[1], ("hi there".to_string(), false));
}

#[tokio::test]
async fn test_session_history_max_events() {
    let mut history = SessionHistory::new(5);
    
    for i in 0..10 {
        history.add_event(SessionEventType::UserInput(format!("message {}", i)), None);
    }
    
    assert_eq!(history.len(), 5);
    
    let events: Vec<_> = history.get_events().iter().collect();
    assert_eq!(events.len(), 5);
}

#[tokio::test]
async fn test_routing_context() {
    use orchestrator_core::session::{RoutingContext, ExecutorTarget};
    
    let mut context = RoutingContext::new();
    
    assert!(context.target_executor.is_none());
    assert!(!context.requires_confirmation);
    
    context.set_target(ExecutorTarget::Claude, true);
    assert!(matches!(context.target_executor, Some(ExecutorTarget::Claude)));
    assert!(context.requires_confirmation);
    
    context.clear_target();
    assert!(context.target_executor.is_none());
    assert!(!context.requires_confirmation);
}