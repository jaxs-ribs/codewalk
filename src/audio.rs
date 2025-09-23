use std::{
    collections::HashSet,
    io::Cursor,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

use anyhow::{Context, Result, anyhow};
use audrey::Reader as AudioReader;
use chrono::Local;
use cpal::{
    SampleFormat, Stream,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};
use device_query::{DeviceQuery, DeviceState, Keycode};
use rodio::{
    OutputStream, OutputStreamHandle, Sink, Source, buffer::SamplesBuffer, source::SineWave,
};

use crate::tts_backend::{TtsAudio, is_say_process_active, stop_say_process};
use crate::{EXIT_KEY, PUSH_TO_TALK_KEY, TARGET_SAMPLE_RATE};

pub struct Recorder {
    stream: Stream,
    state: Arc<RecordingState>,
    input_sample_rate: u32,
}

impl Recorder {
    pub fn new() -> Result<Self> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .context("No default audio input device found")?;

        let supported_config = device
            .default_input_config()
            .context("No supported input config for default audio device")?;

        let sample_format = supported_config.sample_format();
        let config: cpal::StreamConfig = supported_config.into();
        let input_sample_rate = config.sample_rate.0;
        let channels = config.channels as usize;

        let state = Arc::new(RecordingState::default());
        let stream = match sample_format {
            SampleFormat::F32 => build_input_stream_f32(&device, &config, state.clone(), channels)?,
            SampleFormat::I16 => build_input_stream_i16(&device, &config, state.clone(), channels)?,
            SampleFormat::U16 => build_input_stream_u16(&device, &config, state.clone(), channels)?,
            other => return Err(anyhow!("Unsupported input sample format: {other:?}")),
        };

        stream
            .play()
            .context("Failed to start audio capture stream")?;

        Ok(Self {
            stream,
            state,
            input_sample_rate,
        })
    }

    pub fn start(&self) {
        {
            let mut buffer = self.state.buffer.lock().expect("recorder buffer poisoned");
            buffer.clear();
        }
        self.state.recording.store(true, Ordering::SeqCst);
    }

    pub fn stop(&self) -> Result<RecordingResult> {
        if !self.state.recording.swap(false, Ordering::SeqCst) {
            return Err(anyhow!("Recorder was not active"));
        }

        // Let the callback drain any buffered frames.
        thread::sleep(Duration::from_millis(50));

        let mut buffer = self.state.buffer.lock().expect("recorder buffer poisoned");
        let samples = std::mem::take(&mut *buffer);

        Ok(RecordingResult {
            samples,
            sample_rate: self.input_sample_rate,
        })
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        let _ = self.stream.pause();
    }
}

#[derive(Default)]
struct RecordingState {
    buffer: Mutex<Vec<f32>>,
    recording: AtomicBool,
}

pub struct RecordingResult {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
}

fn build_input_stream_f32(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    state: Arc<RecordingState>,
    channels: usize,
) -> Result<Stream> {
    let err_fn = |err| eprintln!("Audio input stream error: {err}");

    let stream = device.build_input_stream(
        config,
        move |data: &[f32], _| {
            if !state.recording.load(Ordering::Relaxed) {
                return;
            }

            let mut buffer = state.buffer.lock().expect("recorder buffer poisoned");
            for frame in data.chunks(channels) {
                let mut sum = 0.0f32;
                for &sample in frame {
                    sum += sample.clamp(-1.0, 1.0);
                }
                buffer.push(sum / channels as f32);
            }
        },
        err_fn,
        None,
    )?;

    Ok(stream)
}

fn build_input_stream_i16(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    state: Arc<RecordingState>,
    channels: usize,
) -> Result<Stream> {
    let err_fn = |err| eprintln!("Audio input stream error: {err}");

    let stream = device.build_input_stream(
        config,
        move |data: &[i16], _| {
            if !state.recording.load(Ordering::Relaxed) {
                return;
            }

            let mut buffer = state.buffer.lock().expect("recorder buffer poisoned");
            for frame in data.chunks(channels) {
                let mut sum = 0.0f32;
                for &sample in frame {
                    sum += (sample as f32 / i16::MAX as f32).clamp(-1.0, 1.0);
                }
                buffer.push(sum / channels as f32);
            }
        },
        err_fn,
        None,
    )?;

    Ok(stream)
}

fn build_input_stream_u16(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    state: Arc<RecordingState>,
    channels: usize,
) -> Result<Stream> {
    let err_fn = |err| eprintln!("Audio input stream error: {err}\n");

    let stream = device.build_input_stream(
        config,
        move |data: &[u16], _| {
            if !state.recording.load(Ordering::Relaxed) {
                return;
            }

            let mut buffer = state.buffer.lock().expect("recorder buffer poisoned");
            for frame in data.chunks(channels) {
                let mut sum = 0.0f32;
                for &sample in frame {
                    let normalized = (sample as f32 / u16::MAX as f32) * 2.0 - 1.0;
                    sum += normalized.clamp(-1.0, 1.0);
                }
                buffer.push(sum / channels as f32);
            }
        },
        err_fn,
        None,
    )?;

    Ok(stream)
}

pub struct BeepPlayer {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

impl BeepPlayer {
    pub fn new() -> Result<Self> {
        let (stream, handle) =
            OutputStream::try_default().context("Failed to create audio output stream")?;
        Ok(Self {
            _stream: stream,
            handle,
        })
    }

    pub fn play(&self) -> Result<()> {
        let sink = Sink::try_new(&self.handle).context("Failed to create beep sink")?;
        let source = SineWave::new(880.0)
            .take_duration(Duration::from_millis(160))
            .amplify(0.2);
        sink.append(source);
        sink.detach();
        Ok(())
    }
}

pub struct SpeechPlayer {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

impl SpeechPlayer {
    pub fn new() -> Result<Self> {
        let (stream, handle) =
            OutputStream::try_default().context("Failed to create TTS output stream")?;
        Ok(Self {
            _stream: stream,
            handle,
        })
    }

    pub fn play(&self, audio: &TtsAudio) -> Result<()> {
        if audio.macos_say_token().is_some() {
            // macOS say already handles playback; nothing to do here
            return Ok(());
        }

        if audio.bytes.is_empty() {
            return Err(anyhow!("No audio data supplied for playback"));
        }

        let sink = Sink::try_new(&self.handle).context("Failed to create TTS sink")?;
        let cursor = Cursor::new(audio.bytes.clone());
        let mut reader = match AudioReader::new(cursor) {
            Ok(r) => r,
            Err(err) => {
                return Err(err).context("Failed to read TTS audio");
            }
        };

        let desc = reader.description();
        let channels = u16::try_from(desc.channel_count())
            .map_err(|_| anyhow!("TTS audio channel count exceeds supported range"))?;

        if channels == 0 {
            return Err(anyhow!("TTS audio has zero channels"));
        }

        let sample_rate = desc.sample_rate();
        let samples: Vec<f32> = reader
            .samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|err| anyhow!("Failed to decode TTS audio: {err}"))?;

        let buffer = SamplesBuffer::new(channels, sample_rate, samples);
        sink.append(buffer);
        sink.detach();
        Ok(())
    }

    pub fn play_interruptible(
        &self,
        audio: &TtsAudio,
        interrupt: Arc<AtomicBool>,
        keyboard: &DeviceState,
    ) -> Result<()> {
        if let Some(token) = audio.macos_say_token() {
            loop {
                if !is_say_process_active(token) {
                    break;
                }

                if interrupt.load(Ordering::Relaxed) {
                    if !stop_say_process(Some(token)) {
                        stop_say_process(None);
                    }
                    println!("(playback interrupted)");
                    break;
                }

                let keys: HashSet<Keycode> = keyboard.get_keys().into_iter().collect();
                if keys.contains(&PUSH_TO_TALK_KEY) || keys.contains(&EXIT_KEY) {
                    if !stop_say_process(Some(token)) {
                        stop_say_process(None);
                    }
                    println!("(playback interrupted)");
                    break;
                }

                thread::sleep(Duration::from_millis(10));
            }

            return Ok(());
        }

        if audio.bytes.is_empty() {
            return Err(anyhow!("No audio data supplied for playback"));
        }

        let sink = Sink::try_new(&self.handle).context("Failed to create TTS sink")?;
        let cursor = Cursor::new(audio.bytes.clone());
        let mut reader = match AudioReader::new(cursor) {
            Ok(r) => r,
            Err(err) => {
                return Err(err).context("Failed to read TTS audio");
            }
        };
        let desc = reader.description();
        let channels = u16::try_from(desc.channel_count())
            .map_err(|_| anyhow!("TTS audio channel count exceeds supported range"))?;

        if channels == 0 {
            return Err(anyhow!("TTS audio has zero channels"));
        }

        let sample_rate = desc.sample_rate();
        let samples: Vec<f32> = reader
            .samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|err| anyhow!("Failed to decode TTS audio: {err}"))?;

        let buffer = SamplesBuffer::new(channels, sample_rate, samples);
        sink.append(buffer);

        while !sink.empty() {
            if interrupt.load(Ordering::Relaxed) {
                sink.stop();
                stop_say_process(None);
                return Ok(());
            }

            let keys: HashSet<Keycode> = keyboard.get_keys().into_iter().collect();
            if keys.contains(&PUSH_TO_TALK_KEY) || keys.contains(&EXIT_KEY) {
                sink.stop();
                stop_say_process(None);
                println!("(playback interrupted)");
                return Ok(());
            }

            thread::sleep(Duration::from_millis(10));
        }

        Ok(())
    }
}

pub struct SavedRecording {
    pub path: PathBuf,
    pub duration_seconds: f32,
}

pub fn save_recording(
    result: &RecordingResult,
    output_dir: &Path,
) -> Result<Option<SavedRecording>> {
    if result.samples.is_empty() {
        return Ok(None);
    }

    let resampled = resample_linear(&result.samples, result.sample_rate, TARGET_SAMPLE_RATE);
    if resampled.is_empty() {
        return Ok(None);
    }

    let quantized = quantize_to_i16(&resampled);

    if quantized.is_empty() {
        return Ok(None);
    }

    let filename = format!("recording-{}.wav", Local::now().format("%Y%m%d-%H%M%S%.3f"));
    let path = output_dir.join(filename);

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let duration_seconds = quantized.len() as f32 / TARGET_SAMPLE_RATE as f32;
    let mut writer = hound::WavWriter::create(&path, spec)
        .with_context(|| format!("Failed to create wav file at {}", path.display()))?;
    for sample in &quantized {
        writer
            .write_sample(*sample)
            .context("Failed to write sample to wav file")?;
    }
    writer.finalize().context("Failed to finalize wav file")?;

    Ok(Some(SavedRecording {
        path,
        duration_seconds,
    }))
}

fn resample_linear(samples: &[f32], input_rate: u32, target_rate: u32) -> Vec<f32> {
    if samples.is_empty() || input_rate == 0 || target_rate == 0 {
        return Vec::new();
    }

    if input_rate == target_rate {
        return samples.to_vec();
    }

    let ratio = input_rate as f64 / target_rate as f64;
    let output_len = ((samples.len() as f64) / ratio).round() as usize;
    let output_len = output_len.max(1);

    let mut out = Vec::with_capacity(output_len);
    for i in 0..output_len {
        let src_pos = i as f64 * ratio;
        let base_idx = src_pos.floor() as usize;
        let base_idx = base_idx.min(samples.len().saturating_sub(1));
        let next_idx = (base_idx + 1).min(samples.len().saturating_sub(1));
        let frac = (src_pos - base_idx as f64) as f32;
        let s0 = samples[base_idx];
        let s1 = samples[next_idx];
        out.push(s0 + (s1 - s0) * frac);
    }

    out
}

fn quantize_to_i16(samples: &[f32]) -> Vec<i16> {
    samples
        .iter()
        .map(|&sample| {
            let clamped = sample.clamp(-1.0, 1.0);
            (clamped * i16::MAX as f32) as i16
        })
        .collect()
}
