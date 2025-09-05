use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionEvent {
    pub timestamp: DateTime<Utc>,
    pub event_type: SessionEventType,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SessionEventType {
    Started,
    UserInput(String),
    SystemResponse(String),
    StateTransition { from: String, to: String },
    ExecutorLaunched(String),
    ExecutorCompleted,
    Error(String),
    Completed,
}

pub struct SessionHistory {
    events: VecDeque<SessionEvent>,
    max_events: usize,
}

impl SessionHistory {
    pub fn new(max_events: usize) -> Self {
        Self {
            events: VecDeque::with_capacity(max_events),
            max_events,
        }
    }

    pub fn add_event(&mut self, event_type: SessionEventType, metadata: Option<serde_json::Value>) {
        let event = SessionEvent {
            timestamp: Utc::now(),
            event_type,
            metadata,
        };

        if self.events.len() >= self.max_events {
            self.events.pop_front();
        }
        self.events.push_back(event);
    }

    pub fn get_events(&self) -> &VecDeque<SessionEvent> {
        &self.events
    }

    pub fn get_recent_events(&self, count: usize) -> Vec<SessionEvent> {
        self.events
            .iter()
            .rev()
            .take(count)
            .cloned()
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect()
    }

    pub fn get_events_since(&self, since: DateTime<Utc>) -> Vec<SessionEvent> {
        self.events
            .iter()
            .filter(|e| e.timestamp > since)
            .cloned()
            .collect()
    }

    pub fn clear(&mut self) {
        self.events.clear();
    }

    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    pub fn get_last_user_input(&self) -> Option<String> {
        self.events
            .iter()
            .rev()
            .find_map(|e| match &e.event_type {
                SessionEventType::UserInput(input) => Some(input.clone()),
                _ => None,
            })
    }

    pub fn get_conversation_history(&self) -> Vec<(String, bool)> {
        let mut history = Vec::new();
        for event in &self.events {
            match &event.event_type {
                SessionEventType::UserInput(input) => {
                    history.push((input.clone(), true));
                }
                SessionEventType::SystemResponse(response) => {
                    history.push((response.clone(), false));
                }
                _ => {}
            }
        }
        history
    }

    pub fn to_summary(&self) -> SessionSummary {
        let start_time = self.events.front().map(|e| e.timestamp);
        let end_time = self.events.back().map(|e| e.timestamp);
        
        let mut user_input_count = 0;
        let mut system_response_count = 0;
        let mut error_count = 0;
        let mut executor_launches = 0;

        for event in &self.events {
            match &event.event_type {
                SessionEventType::UserInput(_) => user_input_count += 1,
                SessionEventType::SystemResponse(_) => system_response_count += 1,
                SessionEventType::Error(_) => error_count += 1,
                SessionEventType::ExecutorLaunched(_) => executor_launches += 1,
                _ => {}
            }
        }

        SessionSummary {
            start_time,
            end_time,
            total_events: self.events.len(),
            user_input_count,
            system_response_count,
            error_count,
            executor_launches,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSummary {
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
    pub total_events: usize,
    pub user_input_count: usize,
    pub system_response_count: usize,
    pub error_count: usize,
    pub executor_launches: usize,
}

impl Default for SessionHistory {
    fn default() -> Self {
        Self::new(1000)
    }
}