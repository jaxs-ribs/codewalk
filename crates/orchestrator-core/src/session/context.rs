use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionContext {
    pub session_id: Uuid,
    pub user_id: Option<String>,
    pub project_path: Option<String>,
    pub executor_id: Option<String>,
    pub metadata: HashMap<String, serde_json::Value>,
    pub active_prompt: Option<String>,
    pub confirmation_pending: bool,
    pub routing_context: RoutingContext,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingContext {
    pub last_router_response: Option<String>,
    pub requires_confirmation: bool,
    pub target_executor: Option<ExecutorTarget>,
    pub retry_count: u32,
    pub max_retries: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ExecutorTarget {
    Claude,
    Custom(String),
}

impl SessionContext {
    pub fn new() -> Self {
        Self {
            session_id: Uuid::new_v4(),
            user_id: None,
            project_path: None,
            executor_id: None,
            metadata: HashMap::new(),
            active_prompt: None,
            confirmation_pending: false,
            routing_context: RoutingContext::new(),
        }
    }

    pub fn with_user_id(mut self, user_id: String) -> Self {
        self.user_id = Some(user_id);
        self
    }

    pub fn with_project_path(mut self, path: String) -> Self {
        self.project_path = Some(path);
        self
    }

    pub fn set_active_prompt(&mut self, prompt: String) {
        self.active_prompt = Some(prompt);
    }

    pub fn clear_active_prompt(&mut self) {
        self.active_prompt = None;
    }

    pub fn set_executor_id(&mut self, id: String) {
        self.executor_id = Some(id);
    }

    pub fn clear_executor_id(&mut self) {
        self.executor_id = None;
    }

    pub fn set_metadata(&mut self, key: String, value: serde_json::Value) {
        self.metadata.insert(key, value);
    }

    pub fn get_metadata(&self, key: &str) -> Option<&serde_json::Value> {
        self.metadata.get(key)
    }

    pub fn remove_metadata(&mut self, key: &str) -> Option<serde_json::Value> {
        self.metadata.remove(key)
    }

    pub fn reset_routing_context(&mut self) {
        self.routing_context = RoutingContext::new();
    }

    pub fn increment_retry(&mut self) -> bool {
        if self.routing_context.retry_count < self.routing_context.max_retries {
            self.routing_context.retry_count += 1;
            true
        } else {
            false
        }
    }

    pub fn should_retry(&self) -> bool {
        self.routing_context.retry_count < self.routing_context.max_retries
    }
}

impl RoutingContext {
    pub fn new() -> Self {
        Self {
            last_router_response: None,
            requires_confirmation: false,
            target_executor: None,
            retry_count: 0,
            max_retries: 3,
        }
    }

    pub fn set_router_response(&mut self, response: String) {
        self.last_router_response = Some(response);
    }

    pub fn set_target(&mut self, target: ExecutorTarget, requires_confirmation: bool) {
        self.target_executor = Some(target);
        self.requires_confirmation = requires_confirmation;
    }

    pub fn clear_target(&mut self) {
        self.target_executor = None;
        self.requires_confirmation = false;
    }

    pub fn reset(&mut self) {
        *self = Self::new();
    }
}

impl Default for SessionContext {
    fn default() -> Self {
        Self::new()
    }
}

impl Default for RoutingContext {
    fn default() -> Self {
        Self::new()
    }
}