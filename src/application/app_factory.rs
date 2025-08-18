use anyhow::Result;
use crate::application::RecordingSession;
use crate::audio::{CpalAudioRecorder, WavProcessor};
use crate::services::{GroqTranscriptionService, SystemClipboardService, EnvironmentConfigProvider};
use crate::ui::TerminalUI;
use crate::interfaces::ConfigurationProvider;

pub struct ApplicationFactory;

impl ApplicationFactory {
    pub fn create_recording_session() -> Result<RecordingSession> {
        let config = Self::create_configuration()?;
        let api_key = config.get_api_key()?;
        
        let audio_recorder = Box::new(CpalAudioRecorder::new()?);
        let transcription = Box::new(GroqTranscriptionService::new(api_key)?);
        let clipboard = Box::new(SystemClipboardService::new());
        let processor = Box::new(WavProcessor::new());
        let ui = Box::new(TerminalUI::new());
        
        Ok(RecordingSession::new(
            audio_recorder,
            transcription,
            clipboard,
            processor,
            ui,
        ))
    }

    fn create_configuration() -> Result<Box<dyn ConfigurationProvider>> {
        Ok(Box::new(EnvironmentConfigProvider::new()?))
    }
}