use anyhow::Result;
use crate::interfaces::AudioProcessor;
use crate::constants::{SAMPLE_RATE_16KHZ, WAV_BITS_PER_SAMPLE, WAV_CHANNELS};

pub struct WavProcessor;

impl WavProcessor {
    pub fn new() -> Self {
        Self
    }
}

impl AudioProcessor for WavProcessor {
    fn samples_to_wav(&self, samples: &[f32], sample_rate: u32) -> Result<Vec<u8>> {
        let spec = self.create_wav_spec();
        let mut buffer = Vec::new();
        
        {
            let mut writer = hound::WavWriter::new(std::io::Cursor::new(&mut buffer), spec)?;
            let resampler = AudioResampler::new(sample_rate, spec.sample_rate);
            resampler.resample_and_write(&mut writer, samples)?;
            writer.finalize()?;
        }
        
        Ok(buffer)
    }
}

impl WavProcessor {
    fn create_wav_spec(&self) -> hound::WavSpec {
        hound::WavSpec {
            channels: WAV_CHANNELS,
            sample_rate: SAMPLE_RATE_16KHZ,
            bits_per_sample: WAV_BITS_PER_SAMPLE,
            sample_format: hound::SampleFormat::Int,
        }
    }
}

struct AudioResampler {
    input_rate: u32,
    output_rate: u32,
}

impl AudioResampler {
    fn new(input_rate: u32, output_rate: u32) -> Self {
        Self {
            input_rate,
            output_rate,
        }
    }

    fn resample_and_write(
        &self,
        writer: &mut hound::WavWriter<std::io::Cursor<&mut Vec<u8>>>,
        samples: &[f32],
    ) -> Result<()> {
        let resample_ratio = self.calculate_ratio();
        let mut position = 0.0;
        
        while (position as usize) < samples.len() {
            let sample = samples[position as usize];
            let amplitude = SampleConverter::to_i16(sample);
            writer.write_sample(amplitude)?;
            position += resample_ratio;
        }
        
        Ok(())
    }

    fn calculate_ratio(&self) -> f32 {
        self.input_rate as f32 / self.output_rate as f32
    }
}

struct SampleConverter;

impl SampleConverter {
    fn to_i16(sample: f32) -> i16 {
        let clamped = sample.clamp(-1.0, 1.0);
        (clamped * i16::MAX as f32) as i16
    }
}