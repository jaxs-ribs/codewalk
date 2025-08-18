use anyhow::Result;
use async_trait::async_trait;

#[async_trait]
pub trait AudioRecorder {
    fn start_recording(&mut self) -> Result<()>;
    fn stop_recording(&mut self) -> Result<Vec<f32>>;
    fn is_recording(&self) -> bool;
}

#[async_trait]
pub trait TranscriptionService: Send + Sync {
    async fn transcribe(&self, audio_data: Vec<u8>) -> Result<String>;
}

pub trait ClipboardService: Send + Sync {
    fn copy_to_clipboard(&self, text: &str) -> Result<()>;
}

pub trait UserInterface: Send + Sync {
    fn show_recording(&self) -> Result<()>;
    fn show_processing(&self) -> Result<()>;
    fn show_success(&self, text: &str) -> Result<()>;
    fn show_error(&self, error: &str) -> Result<()>;
    fn show_warning(&self, message: &str) -> Result<()>;
}

pub trait ConfigurationProvider: Send + Sync {
    fn get_api_key(&self) -> Result<String>;
    fn get_setting(&self, key: &str) -> Option<String>;
}

pub trait AudioProcessor: Send + Sync {
    fn samples_to_wav(&self, samples: &[f32], sample_rate: u32) -> Result<Vec<u8>>;
}