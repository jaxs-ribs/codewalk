use anyhow::{Result, anyhow};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};

pub struct AudioRecorder {
    samples: Arc<Mutex<Vec<f32>>>,
    stream: Option<cpal::Stream>,
    sample_rate: Option<u32>,
}

impl AudioRecorder {
    pub fn new() -> Result<Self> {
        Ok(Self {
            samples: Arc::new(Mutex::new(Vec::new())),
            stream: None,
            sample_rate: None,
        })
    }

    pub fn start_recording(&mut self) -> Result<()> {
        let device = get_default_input_device()?;
        
        // Try to get a config at 16kHz first (to avoid resampling)
        let config = if let Ok(supported_configs) = device.supported_input_configs() {
            let mut found_16k = None;
            for config in supported_configs {
                if config.min_sample_rate().0 <= 16000 && config.max_sample_rate().0 >= 16000 {
                    // Found a config that supports 16kHz
                    found_16k = Some(config.with_sample_rate(cpal::SampleRate(16000)));
                    break;
                }
            }
            found_16k.unwrap_or_else(|| device.default_input_config().unwrap())
        } else {
            device.default_input_config()?
        };
        
        // Store the actual sample rate from the device
        self.sample_rate = Some(config.sample_rate().0);
        
        self.clear_samples();
        let stream = create_input_stream(&device, &config, Arc::clone(&self.samples))?;
        
        stream.play()?;
        self.stream = Some(stream);
        
        Ok(())
    }

    pub fn stop_recording(&mut self) -> Result<Vec<f32>> {
        if let Some(stream) = self.stream.take() {
            drop(stream);
        }
        
        // Use std::mem::take to avoid cloning
        Ok(self.take_samples())
    }

    pub fn samples_to_wav(&self, samples: &[f32]) -> Result<Vec<u8>> {
        let sample_rate = self.sample_rate.unwrap_or(44100);
        create_wav_from_samples(samples, sample_rate)
    }

    pub fn get_sample_rate(&self) -> u32 {
        self.sample_rate.unwrap_or(44100)
    }

    fn clear_samples(&self) {
        self.samples.lock().unwrap().clear();
    }

    fn take_samples(&self) -> Vec<f32> {
        // Take ownership without cloning
        let mut samples = self.samples.lock().unwrap();
        std::mem::take(&mut *samples)
    }
}

fn get_default_input_device() -> Result<cpal::Device> {
    let host = cpal::default_host();
    host.default_input_device()
        .ok_or_else(|| anyhow!("No input device available"))
}

fn create_input_stream(
    device: &cpal::Device,
    config: &cpal::SupportedStreamConfig,
    samples: Arc<Mutex<Vec<f32>>>,
) -> Result<cpal::Stream> {
    let stream_config = config.config();
    match config.sample_format() {
        cpal::SampleFormat::F32 => build_stream::<f32>(device, &stream_config, samples),
        cpal::SampleFormat::I16 => build_stream::<i16>(device, &stream_config, samples),
        cpal::SampleFormat::U16 => build_stream::<u16>(device, &stream_config, samples),
    }
}

fn build_stream<T>(
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
            handle_audio_data(data, &samples);
        },
        err_fn,
    )?;
    
    Ok(stream)
}

fn handle_audio_data<T>(data: &[T], samples: &Arc<Mutex<Vec<f32>>>)
where
    T: cpal::Sample,
{
    let mut samples = samples.lock().unwrap();
    for sample in data {
        samples.push(sample.to_f32());
    }
}

fn create_wav_from_samples(samples: &[f32], input_rate: u32) -> Result<Vec<u8>> {
    let spec = wav_spec_16khz_mono();
    
    // Pre-allocate buffer with estimated size
    let estimated_size = (samples.len() * 2) + 44; // 16-bit samples + WAV header
    let mut buffer = Vec::with_capacity(estimated_size);
    
    {
        let mut writer = hound::WavWriter::new(std::io::Cursor::new(&mut buffer), spec)?;
        
        // Skip resampling if already at 16kHz
        if input_rate == 16000 {
            for &sample in samples {
                let amplitude = convert_to_i16(sample);
                writer.write_sample(amplitude)?;
            }
        } else {
            write_resampled_audio(&mut writer, samples, input_rate, spec.sample_rate)?;
        }
        
        writer.finalize()?;
    }
    
    Ok(buffer)
}

fn wav_spec_16khz_mono() -> hound::WavSpec {
    hound::WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    }
}

fn write_resampled_audio(
    writer: &mut hound::WavWriter<std::io::Cursor<&mut Vec<u8>>>,
    samples: &[f32],
    input_rate: u32,
    output_rate: u32,
) -> Result<()> {
    let resample_ratio = output_rate as f32 / input_rate as f32;
    let mut position = 0.0;
    
    while (position as usize) < samples.len() {
        let sample = samples[position as usize];
        let amplitude = convert_to_i16(sample);
        writer.write_sample(amplitude)?;
        position += 1.0 / resample_ratio;
    }
    
    Ok(())
}

fn convert_to_i16(sample: f32) -> i16 {
    (sample * i16::MAX as f32) as i16
}