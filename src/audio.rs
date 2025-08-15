use anyhow::{Result, anyhow};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};

pub struct AudioRecorder {
    samples: Arc<Mutex<Vec<f32>>>,
    stream: Option<cpal::Stream>,
}

impl AudioRecorder {
    pub fn new() -> Result<Self> {
        Ok(Self {
            samples: Arc::new(Mutex::new(Vec::new())),
            stream: None,
        })
    }

    pub fn start_recording(&mut self) -> Result<()> {
        let device = get_default_input_device()?;
        let config = device.default_input_config()?;
        
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
        
        Ok(self.get_samples())
    }

    pub fn samples_to_wav(&self, samples: &[f32], sample_rate: u32) -> Result<Vec<u8>> {
        create_wav_from_samples(samples, sample_rate)
    }

    fn clear_samples(&self) {
        self.samples.lock().unwrap().clear();
    }

    fn get_samples(&self) -> Vec<f32> {
        self.samples.lock().unwrap().clone()
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
    let mut buffer = Vec::new();
    
    {
        let mut writer = hound::WavWriter::new(std::io::Cursor::new(&mut buffer), spec)?;
        write_resampled_audio(&mut writer, samples, input_rate, spec.sample_rate)?;
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