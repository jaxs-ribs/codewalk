use anyhow::Result;
use crate::{audio, groq, clipboard, ui};

pub struct App {
    recorder: audio::AudioRecorder,
    groq_client: groq::GroqClient,
    is_recording: bool,
}

impl App {
    pub fn new(api_key: String) -> Result<Self> {
        Ok(Self {
            recorder: audio::AudioRecorder::new()?,
            groq_client: groq::GroqClient::new(api_key)?,
            is_recording: false,
        })
    }

    pub fn is_recording(&self) -> bool {
        self.is_recording
    }

    pub fn toggle_recording(&mut self) -> Result<()> {
        if self.is_recording {
            self.stop_recording()
        } else {
            self.start_recording()
        }
    }

    pub fn start_recording(&mut self) -> Result<()> {
        if self.is_recording {
            return Ok(());
        }
        
        ui::show_recording()?;
        self.recorder.start_recording()?;
        self.is_recording = true;
        Ok(())
    }

    pub fn stop_recording(&mut self) -> Result<()> {
        if !self.is_recording {
            return Ok(());
        }
        
        self.is_recording = false;
        Ok(())
    }

    pub async fn process_recording(&mut self) -> Result<()> {
        if self.is_recording {
            return Ok(());
        }

        ui::show_processing()?;
        
        let samples = self.recorder.stop_recording()?;
        
        if samples.is_empty() {
            ui::show_no_audio()?;
            return Ok(());
        }

        self.transcribe_and_copy(samples).await
    }

    async fn transcribe_and_copy(&mut self, samples: Vec<f32>) -> Result<()> {
        let wav_data = self.create_wav(samples)?;
        let transcription = self.get_transcription(wav_data).await;
        
        match transcription {
            Ok(text) if !text.trim().is_empty() => {
                self.copy_to_clipboard(&text)?;
            }
            Ok(_) => {
                ui::show_no_speech()?;
            }
            Err(e) => {
                ui::show_error(&e.to_string())?;
            }
        }
        
        Ok(())
    }

    fn create_wav(&self, samples: Vec<f32>) -> Result<Vec<u8>> {
        self.recorder.samples_to_wav(&samples, 44100)
    }

    async fn get_transcription(&self, wav_data: Vec<u8>) -> Result<String> {
        self.groq_client.transcribe(wav_data).await
    }

    fn copy_to_clipboard(&self, text: &str) -> Result<()> {
        clipboard::copy_to_clipboard(text)?;
        ui::show_copied(text)?;
        Ok(())
    }
}