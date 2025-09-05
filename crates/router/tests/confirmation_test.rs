#[cfg(test)]
mod tests {
    use router::confirmation::{analyze_confirmation_response, create_confirmation_response};
    use router::RouterAction;

    #[test]
    fn test_continue_previous_patterns() {
        let inputs = vec![
            "continue",
            "continue previous",
            "resume",
            "keep going",
            "yes continue",
            "continue the previous session",
            "resume previous",
            "Continue",
            "CONTINUE",
        ];
        
        for input in inputs {
            let action = analyze_confirmation_response(input);
            assert_eq!(action, RouterAction::ContinuePrevious, 
                "Failed for input: '{}'", input);
        }
    }

    #[test]
    fn test_start_new_patterns() {
        let inputs = vec![
            "new",
            "start new",
            "fresh",
            "start fresh",
            "new session",
            "begin new",
            "NEW",
            "Start New",
        ];
        
        for input in inputs {
            let action = analyze_confirmation_response(input);
            assert_eq!(action, RouterAction::StartNew, 
                "Failed for input: '{}'", input);
        }
    }

    #[test]
    fn test_decline_patterns() {
        let inputs = vec![
            "no",
            "cancel",
            "stop",
            "never mind",
            "forget it",
            "NO",
            "Cancel",
        ];
        
        for input in inputs {
            let action = analyze_confirmation_response(input);
            assert_eq!(action, RouterAction::DeclineSession, 
                "Failed for input: '{}'", input);
        }
    }

    #[test]
    fn test_ambiguous_patterns() {
        let inputs = vec![
            "yes",
            "ok",
            "sure",
            "yeah",
            "yep",
            "okay",
            "alright",
            "go ahead",
            "YES",
            "Ok",
        ];
        
        for input in inputs {
            let action = analyze_confirmation_response(input);
            assert_eq!(action, RouterAction::AmbiguousConfirmation, 
                "Failed for input: '{}'", input);
        }
    }

    #[test]
    fn test_unintelligible_responses() {
        let inputs = vec![
            "what?",
            "huh?",
            "maybe",
            "I don't know",
            "help",
            "foo bar baz",
            "123456",
            "",
        ];
        
        for input in inputs {
            let action = analyze_confirmation_response(input);
            assert_eq!(action, RouterAction::UnintelligibleResponse, 
                "Failed for input: '{}'", input);
        }
    }

    #[test]
    fn test_confirmation_response_creation() {
        // Test that responses are created correctly
        let response = create_confirmation_response(RouterAction::ContinuePrevious);
        assert_eq!(response.action, RouterAction::ContinuePrevious);
        assert!(response.prompt.is_none());
        assert_eq!(response.reason, Some("User wants to continue previous session".to_string()));

        let response = create_confirmation_response(RouterAction::StartNew);
        assert_eq!(response.action, RouterAction::StartNew);
        assert_eq!(response.reason, Some("User wants to start a new session".to_string()));
        
        let response = create_confirmation_response(RouterAction::DeclineSession);
        assert_eq!(response.action, RouterAction::DeclineSession);
        assert_eq!(response.reason, Some("User declined to start a session".to_string()));
    }
}