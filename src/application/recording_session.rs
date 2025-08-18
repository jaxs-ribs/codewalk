use anyhow::Result;
use crate::interfaces::{AudioRecorder, TranscriptionService, ClipboardService, UserInterface, AudioProcessor};
use crate::constants::SAMPLE_RATE_44KHZ;

pub struct RecordingSession {
    audio_recorder: Box<dyn AudioRecorder>,
    transcription_service: Box<dyn TranscriptionService>,
    clipboard_service: Box<dyn ClipboardService>,
    audio_processor: Box<dyn AudioProcessor>,
    ui: Box<dyn UserInterface>,
    pending_samples: Option<Vec<f32>>,
}

impl RecordingSession {
    pub fn new(
        audio_recorder: Box<dyn AudioRecorder>,
        transcription_service: Box<dyn TranscriptionService>,
        clipboard_service: Box<dyn ClipboardService>,
        audio_processor: Box<dyn AudioProcessor>,
        ui: Box<dyn UserInterface>,
    ) -> Self {
        Self {
            audio_recorder,
            transcription_service,
            clipboard_service,
            audio_processor,
            ui,
            pending_samples: None,
        }
    }

    pub fn is_recording(&self) -> bool {
        self.audio_recorder.is_recording()
    }

    pub fn toggle_recording(&mut self) -> Result<()> {
        if self.is_recording() {
            self.stop_recording()
        } else {
            self.start_recording()
        }
    }

    pub async fn process_recording(&mut self) -> Result<()> {
        if self.is_recording() {
            return Ok(());
        }

        self.ui.show_processing()?;
        
        let samples = self.pending_samples.take().unwrap_or_default();
        
        if samples.is_empty() {
            self.ui.show_warning("No audio recorded")?;
            return Ok(());
        }

        self.transcribe_and_save(samples).await
    }

    fn start_recording(&mut self) -> Result<()> {
        self.ui.show_recording()?;
        self.audio_recorder.start_recording()
    }

    fn stop_recording(&mut self) -> Result<()> {
        let samples = self.audio_recorder.stop_recording()?;
        self.pending_samples = Some(samples);
        Ok(())
    }

    async fn transcribe_and_save(&mut self, samples: Vec<f32>) -> Result<()> {
        let transcription = self.get_transcription(samples).await;
        
        match transcription {
            Ok(text) if !text.trim().is_empty() => {
                self.save_to_clipboard(&text)?;
            }
            Ok(_) => {
                self.ui.show_warning("No speech detected")?;
            }
            Err(e) => {
                self.ui.show_error(&e.to_string())?;
            }
        }
        
        Ok(())
    }

    async fn get_transcription(&self, samples: Vec<f32>) -> Result<String> {
        let wav_data = self.audio_processor.samples_to_wav(&samples, SAMPLE_RATE_44KHZ)?;
        self.transcription_service.transcribe(wav_data).await
    }

    fn save_to_clipboard(&self, text: &str) -> Result<()> {
        self.clipboard_service.copy_to_clipboard(text)?;
        self.ui.show_success(text)
    }
}