use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use chrono::Local;
use cpal::{
    SampleFormat, Stream,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};
use device_query::{DeviceQuery, DeviceState, Keycode};
use rodio::{OutputStream, OutputStreamHandle, Sink, Source, source::SineWave};

const TARGET_SAMPLE_RATE: u32 = 16_000;
const PUSH_TO_TALK_KEY: Keycode = Keycode::Space;
const EXIT_KEY: Keycode = Keycode::Escape;
const OUTPUT_DIR: &str = "recordings";

fn main() -> Result<()> {
    let env_source = load_env_file()?;

    ensure_groq_key(env_source.as_deref())?;

    let mut app = App::new()?;
    app.run()?;

    Ok(())
}

fn load_env_file() -> Result<Option<PathBuf>> {
    match dotenvy::dotenv() {
        Ok(path) => Ok(Some(path)),
        Err(err) => {
            if err.not_found() {
                Ok(None)
            } else {
                Err(anyhow!("Failed to load environment from .env: {err}"))
            }
        }
    }
}

fn ensure_groq_key(env_source: Option<&Path>) -> Result<()> {
    hydrate_env_var_from_files("GROQ_API_KEY", env_source)?;

    let key = std::env::var("GROQ_API_KEY")
        .context("Missing GROQ_API_KEY. Add it to your .env file before running walkcoach.")?;

    if key.trim().is_empty() {
        return Err(anyhow!(
            "GROQ_API_KEY is set but empty. Add a valid key to your .env file before running walkcoach."
        ));
    }

    Ok(())
}

fn hydrate_env_var_from_files(name: &str, env_source: Option<&Path>) -> Result<()> {
    if std::env::var(name).is_ok() {
        return Ok(());
    }

    if let Some(value) = locate_env_var(name, env_source)? {
        // SAFETY: restricted to startup before worker threads spin up.
        unsafe {
            std::env::set_var(name, &value);
        }
    }

    Ok(())
}

fn locate_env_var(name: &str, env_source: Option<&Path>) -> Result<Option<String>> {
    if let Some(path) = env_source {
        if let Some(value) = read_var_from_path(name, path)? {
            return Ok(Some(value));
        }
    }

    for candidate in [".env", ".env.local", "config/.env"] {
        let path = Path::new(candidate);
        if let Some(value) = read_var_from_path(name, path)? {
            return Ok(Some(value));
        }
    }

    Ok(None)
}

fn read_var_from_path(name: &str, path: &Path) -> Result<Option<String>> {
    if !path.exists() {
        return Ok(None);
    }

    let iter = dotenvy::from_path_iter(path)
        .map_err(|err| anyhow!("Failed to read environment file {}: {err}", path.display()))?;

    for entry in iter {
        let (key, value) = entry.map_err(|err| {
            anyhow!(
                "Failed to parse environment entry in {}: {err}",
                path.display()
            )
        })?;
        if key == name {
            return Ok(Some(value));
        }
    }

    Ok(None)
}

struct App {
    recorder: Recorder,
    beep: BeepPlayer,
    keyboard: DeviceState,
    output_dir: PathBuf,
}

impl App {
    fn new() -> Result<Self> {
        let recorder = Recorder::new()?;
        let beep = BeepPlayer::new()?;
        let keyboard = DeviceState::new();
        let output_dir = PathBuf::from(OUTPUT_DIR);
        fs::create_dir_all(&output_dir).context("Failed to create recordings directory")?;

        Ok(Self {
            recorder,
            beep,
            keyboard,
            output_dir,
        })
    }

    fn run(&mut self) -> Result<()> {
        println!("Ready. Hold Space to record, release to stop. Press Esc to exit.");

        let mut recording_active = false;
        let mut started_at: Option<Instant> = None;

        loop {
            let keys: HashSet<Keycode> = self.keyboard.get_keys().into_iter().collect();
            let is_down = keys.contains(&PUSH_TO_TALK_KEY);

            if keys.contains(&EXIT_KEY) && !is_down && !recording_active {
                println!("Exiting. See your clips in {OUTPUT_DIR}/");
                break;
            }

            if is_down && !recording_active {
                self.recorder.start();
                recording_active = true;
                started_at = Some(Instant::now());
                println!("Recording...");
            } else if !is_down && recording_active {
                recording_active = false;
                let elapsed = started_at
                    .map(|instant| instant.elapsed())
                    .unwrap_or_default();
                let capture = self.recorder.stop()?;
                self.beep.play()?;

                match save_recording(&capture, &self.output_dir) {
                    Ok(Some(saved)) => {
                        let reported_duration = saved.duration_seconds;
                        println!(
                            "Saved {} ({reported_duration:.2}s captured, key held for {:.2}s)",
                            saved.path.display(),
                            elapsed.as_secs_f32()
                        );
                    }
                    Ok(None) => println!("No audio detected. Nothing saved."),
                    Err(err) => eprintln!("Failed to save recording: {err:?}"),
                }

                started_at = None;
            }

            thread::sleep(Duration::from_millis(12));
        }

        Ok(())
    }
}

struct Recorder {
    _stream: Stream,
    state: Arc<RecordingState>,
    input_sample_rate: u32,
}

impl Recorder {
    fn new() -> Result<Self> {
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
            _stream: stream,
            state,
            input_sample_rate,
        })
    }

    fn start(&self) {
        {
            let mut buffer = self.state.buffer.lock().expect("recorder buffer poisoned");
            buffer.clear();
        }
        self.state.recording.store(true, Ordering::SeqCst);
    }

    fn stop(&self) -> Result<RecordingResult> {
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

#[derive(Default)]
struct RecordingState {
    buffer: Mutex<Vec<f32>>,
    recording: AtomicBool,
}

struct RecordingResult {
    samples: Vec<f32>,
    sample_rate: u32,
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
                let sum: f32 = frame.iter().copied().sum();
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
                    let normalized = sample as f32 / i16::MAX as f32;
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

fn build_input_stream_u16(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    state: Arc<RecordingState>,
    channels: usize,
) -> Result<Stream> {
    let err_fn = |err| eprintln!("Audio input stream error: {err}");

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

struct BeepPlayer {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

impl BeepPlayer {
    fn new() -> Result<Self> {
        let (stream, handle) =
            OutputStream::try_default().context("Failed to create audio output stream")?;
        Ok(Self {
            _stream: stream,
            handle,
        })
    }

    fn play(&self) -> Result<()> {
        let sink = Sink::try_new(&self.handle).context("Failed to create beep sink")?;
        let source = SineWave::new(880.0)
            .take_duration(Duration::from_millis(160))
            .amplify(0.2);
        sink.append(source);
        sink.detach();
        Ok(())
    }
}

struct SavedRecording {
    path: PathBuf,
    duration_seconds: f32,
}

fn save_recording(result: &RecordingResult, output_dir: &Path) -> Result<Option<SavedRecording>> {
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
