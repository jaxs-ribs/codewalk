use anyhow::{Result, anyhow};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};
use async_trait::async_trait;
use crate::interfaces::AudioRecorder;

pub struct CpalAudioRecorder {
    samples: Arc<Mutex<Vec<f32>>>,
    stream: Option<cpal::Stream>,
    recording: bool,
}

impl CpalAudioRecorder {
    pub fn new() -> Result<Self> {
        Ok(Self {
            samples: Arc::new(Mutex::new(Vec::new())),
            stream: None,
            recording: false,
        })
    }

    fn clear_samples(&self) {
        self.samples.lock().unwrap().clear();
    }

    fn get_samples(&self) -> Vec<f32> {
        self.samples.lock().unwrap().clone()
    }
}

#[async_trait]
impl AudioRecorder for CpalAudioRecorder {
    fn start_recording(&mut self) -> Result<()> {
        if self.recording {
            return Ok(());
        }

        let device = AudioDeviceManager::get_default_input()?;
        let config = device.default_input_config()?;
        
        self.clear_samples();
        let stream = StreamBuilder::build(&device, &config, Arc::clone(&self.samples))?;
        
        stream.play()?;
        self.stream = Some(stream);
        self.recording = true;
        
        Ok(())
    }

    fn stop_recording(&mut self) -> Result<Vec<f32>> {
        if !self.recording {
            return Ok(Vec::new());
        }

        if let Some(stream) = self.stream.take() {
            drop(stream);
        }
        
        self.recording = false;
        Ok(self.get_samples())
    }

    fn is_recording(&self) -> bool {
        self.recording
    }
}

struct AudioDeviceManager;

impl AudioDeviceManager {
    fn get_default_input() -> Result<cpal::Device> {
        let host = cpal::default_host();
        host.default_input_device()
            .ok_or_else(|| anyhow!("No input device available"))
    }
}

struct StreamBuilder;

impl StreamBuilder {
    fn build(
        device: &cpal::Device,
        config: &cpal::SupportedStreamConfig,
        samples: Arc<Mutex<Vec<f32>>>,
    ) -> Result<cpal::Stream> {
        let stream_config = config.config();
        match config.sample_format() {
            cpal::SampleFormat::F32 => Self::build_typed::<f32>(device, &stream_config, samples),
            cpal::SampleFormat::I16 => Self::build_typed::<i16>(device, &stream_config, samples),
            cpal::SampleFormat::U16 => Self::build_typed::<u16>(device, &stream_config, samples),
        }
    }

    fn build_typed<T>(
        device: &cpal::Device,
        config: &cpal::StreamConfig,
        samples: Arc<Mutex<Vec<f32>>>,
    ) -> Result<cpal::Stream>
    where
        T: cpal::Sample,
    {
        let err_fn = |err| eprintln!("Stream error: {}", err);
        
        let stream = device.build_input_stream(
            config,
            move |data: &[T], _: &cpal::InputCallbackInfo| {
                AudioDataHandler::handle(data, &samples);
            },
            err_fn,
        )?;
        
        Ok(stream)
    }
}

struct AudioDataHandler;

impl AudioDataHandler {
    fn handle<T>(data: &[T], samples: &Arc<Mutex<Vec<f32>>>)
    where
        T: cpal::Sample,
    {
        let mut samples = samples.lock().unwrap();
        for sample in data {
            samples.push(sample.to_f32());
        }
    }
}