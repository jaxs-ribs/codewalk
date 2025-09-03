use std::collections::VecDeque;
use serde::{Deserialize, Serialize};

const MAX_HISTORY_SIZE: usize = 10;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: MessageRole,
    pub content: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageRole {
    User,
    Assistant,
    System,
}

impl Message {
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: MessageRole::User,
            content: content.into(),
            timestamp: chrono::Utc::now(),
        }
    }
    
    pub fn assistant(content: impl Into<String>) -> Self {
        Self {
            role: MessageRole::Assistant,
            content: content.into(),
            timestamp: chrono::Utc::now(),
        }
    }
    
    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: MessageRole::System,
            content: content.into(),
            timestamp: chrono::Utc::now(),
        }
    }
}

pub struct ConversationMemory {
    messages: VecDeque<Message>,
    max_size: usize,
}

impl ConversationMemory {
    pub fn new() -> Self {
        Self::with_max_size(MAX_HISTORY_SIZE)
    }
    
    pub fn with_max_size(max_size: usize) -> Self {
        Self {
            messages: VecDeque::with_capacity(max_size),
            max_size,
        }
    }
    
    pub fn add_message(&mut self, message: Message) {
        // If we're at capacity, remove the oldest message
        if self.messages.len() >= self.max_size {
            self.messages.pop_front();
        }
        self.messages.push_back(message);
    }
    
    pub fn add_user_message(&mut self, content: impl Into<String>) {
        self.add_message(Message::user(content));
    }
    
    pub fn add_assistant_message(&mut self, content: impl Into<String>) {
        self.add_message(Message::assistant(content));
    }
    
    pub fn get_history(&self) -> Vec<Message> {
        self.messages.iter().cloned().collect()
    }
    
    pub fn get_context_for_llm(&self) -> String {
        let mut context = String::new();
        
        if !self.messages.is_empty() {
            context.push_str("\nConversation History (last ");
            context.push_str(&self.messages.len().to_string());
            context.push_str(" messages):\n");
            
            for (i, msg) in self.messages.iter().enumerate() {
                let role = match msg.role {
                    MessageRole::User => "User",
                    MessageRole::Assistant => "Assistant",
                    MessageRole::System => "System",
                };
                
                context.push_str(&format!("{}. [{}]: {}\n", i + 1, role, msg.content));
            }
        }
        
        context
    }
    
    pub fn clear(&mut self) {
        self.messages.clear();
    }
    
    pub fn len(&self) -> usize {
        self.messages.len()
    }
    
    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }
    
    pub fn get_last_assistant_message(&self) -> Option<&str> {
        self.messages.iter()
            .rev()
            .find(|msg| matches!(msg.role, MessageRole::Assistant))
            .map(|msg| msg.content.as_str())
    }
}

impl Default for ConversationMemory {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_memory_capacity() {
        let mut memory = ConversationMemory::with_max_size(3);
        
        memory.add_user_message("Message 1");
        memory.add_assistant_message("Response 1");
        memory.add_user_message("Message 2");
        assert_eq!(memory.len(), 3);
        
        // Adding a 4th message should remove the oldest
        memory.add_assistant_message("Response 2");
        assert_eq!(memory.len(), 3);
        
        let history = memory.get_history();
        assert_eq!(history[0].content, "Response 1");
        assert_eq!(history[2].content, "Response 2");
    }
    
    #[test]
    fn test_context_generation() {
        let mut memory = ConversationMemory::new();
        
        memory.add_user_message("Help me fix a bug");
        memory.add_assistant_message("I'll help you fix the bug");
        
        let context = memory.get_context_for_llm();
        assert!(context.contains("User"));
        assert!(context.contains("Assistant"));
        assert!(context.contains("Help me fix a bug"));
    }
}