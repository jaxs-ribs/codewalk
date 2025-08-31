use serde::{Deserialize, Serialize};

/// Protocol version (bumped when breaking changes are introduced)
pub const VERSION: u8 = 1;

/// Top-level message envelope.
/// Keep variants minimal initially; extend in later phases.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
    UserText(UserText),
    Ack(Ack),
    Status(Status),
    PromptConfirmation(PromptConfirmation),
    // Placeholders for future phases
    // ConfirmResponse(ConfirmResponse),
    // Status(Status),
    // PromptConfirmation(PromptConfirmation),
    // ExecutorStarted(ExecutorStarted),
    // ExecutorOutput(ExecutorOutput),
    // ExecutorEnded(ExecutorEnded),
}

/// Text emitted by a user/input device (phone, TUI, API). Supports partial/final.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserText {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub v: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>, // "phone" | "tui" | "api" | "unknown"
    #[serde(default, skip_serializing_if = "is_false")]
    pub final_: bool,
}

/// A simple acknowledgement message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ack {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub v: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    pub text: String,
}

#[inline]
fn is_false(b: &bool) -> bool { !*b }

impl Message {
    pub fn user_text<S: Into<String>>(text: S, source: Option<String>, final_: bool) -> Self {
        Message::UserText(UserText {
            v: Some(VERSION),
            id: None,
            text: text.into(),
            source,
            final_,
        })
    }

    pub fn ack<S: Into<String>>(text: S, reply_to: Option<String>) -> Self {
        Message::Ack(Ack { v: Some(VERSION), reply_to, text: text.into() })
    }
}

/// Informational status line for UIs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Status {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub v: Option<u8>,
    pub level: String, // info|warn|error
    pub text: String,
}

/// Ask a UI to confirm an action (e.g., launching an executor)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptConfirmation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub v: Option<u8>,
    #[serde(rename = "for")]
    pub for_: String, // "executor_launch"
    pub executor: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub working_dir: Option<String>,
    pub prompt: String,
}
