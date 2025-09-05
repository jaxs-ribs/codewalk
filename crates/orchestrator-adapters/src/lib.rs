pub mod groq;
pub mod relay;
pub mod bridge;

// Lightweight logger shim for adapter logging during tests/builds
pub mod logger {
    #[inline]
    pub fn log_event(_category: &str, _message: &str) {}
    #[inline]
    pub fn log_debug(_message: &str) {}
}

// Re-export groq functions under a `backend` namespace for compatibility
pub mod backend {
    pub use crate::groq::*;
}
