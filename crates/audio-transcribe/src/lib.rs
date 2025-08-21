pub mod recorder;
pub mod traits;
pub mod providers;

pub use recorder::AudioRecorder;
pub use traits::{TranscriptionProvider, TranscriptionResult};

// Re-export providers
pub use providers::groq::GroqProvider;