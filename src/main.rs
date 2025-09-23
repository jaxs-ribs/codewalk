use std::{
    cell::Cell,
    collections::HashSet,
    fs,
    fs::OpenOptions,
    io::{Cursor, Write},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use audrey::Reader as AudioReader;
use base64::{
    Engine as _,
    engine::general_purpose::{STANDARD, URL_SAFE},
};
use chrono::{Local, SecondsFormat, Utc};
use cpal::{
    SampleFormat, Stream,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};
use device_query::{DeviceQuery, DeviceState, Keycode};
use reqwest::{
    blocking::{Client as HttpClient, multipart},
    header::CONTENT_TYPE,
};
use rodio::{
    OutputStream, OutputStreamHandle, Sink, Source, buffer::SamplesBuffer, source::SineWave,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

mod artifacts;
mod orchestrator;

use crate::artifacts::{ArtifactManager, ArtifactUpdateOutcome};
use crate::orchestrator::{Orchestrator, Action};

const TARGET_SAMPLE_RATE: u32 = 16_000;
const PUSH_TO_TALK_KEY: Keycode = Keycode::Space;
const EXIT_KEY: Keycode = Keycode::Escape;
const OUTPUT_DIR: &str = "recordings";
const DEFAULT_STT_LANGUAGE: &str = "en";
const DEFAULT_LLM_TEMPERATURE: f32 = 0.3;
const DEFAULT_LLM_MAX_TOKENS: u32 = 400;
const DEFAULT_LLM_MODEL: &str = "moonshotai/kimi-k2-instruct-0905";
const DEFAULT_TTS_MODEL: &str = "playai-tts";
const DEFAULT_TTS_VOICE: &str = "Fritz-PlayAI";
const SMART_SECRETARY_PROMPT: &str = "You are Walkcoach, a smart secretary. Answer in one to three short sentences. If one clarifier would change the answer, ask it. Otherwise, give tight, actionable guidance. No filler.";

fn main() -> Result<()> {
    let env_source = load_env_file()?;
    ensure_groq_key(env_source.as_deref())?;

    let mut app = App::new()?;
    app.run()
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
        // SAFETY: remaining single-threaded during bootstrap.
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
    speaker: SpeechPlayer,
    keyboard: DeviceState,
    transcriber: TranscriptionClient,
    assistant: AssistantClient,
    tts: TtsClient,
    trace_logger: Option<TraceLogger>,
    artifact_manager: Option<ArtifactManager>,
    orchestrator: Orchestrator,
    output_dir: PathBuf,
}

impl App {
    fn new() -> Result<Self> {
        let recorder = Recorder::new()?;
        let beep = BeepPlayer::new()?;
        let speaker = SpeechPlayer::new()?;
        let keyboard = DeviceState::new();
        let output_dir = PathBuf::from(OUTPUT_DIR);
        fs::create_dir_all(&output_dir).context("Failed to create recordings directory")?;

        let api_key = std::env::var("GROQ_API_KEY")
            .context("GROQ_API_KEY disappeared before we could build the Groq clients")?;
        let transcriber = TranscriptionClient::new(api_key.clone())?;
        let assistant = AssistantClient::new(api_key.clone())?;
        let tts = TtsClient::new(api_key.clone())?;
        let logging_enabled = !matches!(
            std::env::var("WALKCOACH_NO_LOG"),
            Ok(val) if matches!(val.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes")
        );
        let trace_logger = TraceLogger::new(logging_enabled)?;
        let mut artifact_manager = if logging_enabled {
            match ArtifactManager::new(api_key) {
                Ok(manager) => {
                    if let Some(reason) = manager.disabled_reason() {
                        println!("{reason}");
                    }
                    Some(manager)
                }
                Err(err) => {
                    eprintln!("Artifact manager unavailable: {err:?}");
                    None
                }
            }
        } else {
            None
        };

        let mut orchestrator = Orchestrator::new();
        
        // Move artifact manager to orchestrator for Phase 0
        // (In Phase 1, the orchestrator will own all file I/O directly)
        if let Some(manager) = artifact_manager.take() {
            orchestrator.set_artifact_manager(manager);
        }
        
        Ok(Self {
            recorder,
            beep,
            speaker,
            keyboard,
            transcriber,
            assistant,
            tts,
            trace_logger,
            artifact_manager: None, // Moved to orchestrator for Phase 0
            orchestrator,
            output_dir,
        })
    }

    fn run(&mut self) -> Result<()> {
        println!("Ready. Hold Space to record, release to stop. Press Esc to exit.");

        let mut recording_active = false;
        let mut started_at: Option<Instant> = None;

        loop {
            // Process any pending orchestrator actions
            self.process_orchestrator_queue();
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

                let save_result = save_recording(&capture, &self.output_dir);
                started_at = None;

                let saved = match save_result {
                    Ok(Some(saved)) => {
                        let reported_duration = saved.duration_seconds;
                        println!(
                            "Saved {} ({reported_duration:.2}s captured, key held for {:.2}s)",
                            saved.path.display(),
                            elapsed.as_secs_f32()
                        );
                        saved
                    }
                    Ok(None) => {
                        println!("No audio detected. Nothing saved.");
                        continue;
                    }
                    Err(err) => {
                        eprintln!("Failed to save recording: {err:?}");
                        continue;
                    }
                };

                let mut trace_entry = TraceEntry::new("fast");
                trace_entry.durations.record_ms = (saved.duration_seconds * 1000.0).round() as u64;

                let stt_start = Instant::now();
                let transcript = match self.transcriber.transcribe(&saved.path) {
                    Ok(transcript) => {
                        trace_entry.durations.stt_ms = stt_start.elapsed().as_millis() as u64;
                        println!("Transcript: {transcript}");
                        trace_entry.user_text = Some(transcript.clone());
                        transcript
                    }
                    Err(err) => {
                        trace_entry.durations.stt_ms = stt_start.elapsed().as_millis() as u64;
                        let msg = format!("transcription failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("Transcription failed for {}: {err:?}", saved.path.display());
                        self.log_trace(trace_entry);
                        continue;
                    }
                };

                let llm_start = Instant::now();
                let answer = match self.assistant.reply(&transcript) {
                    Ok(answer) => {
                        trace_entry.durations.llm_ms = llm_start.elapsed().as_millis() as u64;
                        println!("Assistant: {answer}");
                        trace_entry.assistant_text = Some(answer.clone());
                        answer
                    }
                    Err(err) => {
                        trace_entry.durations.llm_ms = llm_start.elapsed().as_millis() as u64;
                        let msg = format!("assistant failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("Assistant reply failed: {err:?}");
                        self.log_trace(trace_entry);
                        continue;
                    }
                };

                let tts_start = Instant::now();
                let tts_audio = match self.tts.synthesize(&answer) {
                    Ok(audio) => {
                        trace_entry.durations.tts_ms = tts_start.elapsed().as_millis() as u64;
                        if std::env::var("WALKCOACH_DEBUG_TTS").is_ok() {
                            eprintln!(
                                "[tts-debug] bytes={} content-type={} note={:?}",
                                audio.bytes.len(),
                                audio.content_type,
                                audio.note
                            );
                        }
                        trace_entry.tts = Some(TraceTts {
                            engine: "groq".to_string(),
                            voice: self.tts.voice().to_string(),
                            content_type: audio.content_type.clone(),
                            note: audio.note.clone(),
                        });
                        Some(audio)
                    }
                    Err(err) => {
                        trace_entry.durations.tts_ms = tts_start.elapsed().as_millis() as u64;
                        let msg = format!("tts failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("TTS synthesis failed: {err:?}");
                        self.log_trace(trace_entry);
                        continue;
                    }
                };

                if let Some(audio) = &tts_audio {
                    let speak_start = Instant::now();
                    if let Err(err) = self.speaker.play(audio) {
                        let msg = format!("playback failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("Playback failed: {err:?}");
                    }
                    trace_entry.durations.speak_ms = speak_start.elapsed().as_millis() as u64;
                }

                // Queue artifact processing through orchestrator
                // Now guaranteed to run single-threaded
                let action = Action::ProcessArtifacts {
                    transcript: transcript.clone(),
                    reply: answer.clone(),
                };
                
                if let Err(err) = self.orchestrator.enqueue(action) {
                    eprintln!("Failed to queue artifact processing: {err:?}");
                }

                self.log_trace(trace_entry);
                
                // Process queued actions (single-threaded execution)
                self.process_orchestrator_queue();
            }

            thread::sleep(Duration::from_millis(12));
        }

        Ok(())
    }

    fn process_orchestrator_queue(&mut self) {
        // Execute actions from the queue (single-threaded, one at a time)
        while self.orchestrator.has_pending() {
            match self.orchestrator.execute_next() {
                Ok(Some(result)) => {
                    // Handle artifact processing outcome
                    if let Some(outcome) = result.artifact_outcome {
                        self.report_artifact_outcome(outcome);
                    }
                }
                Ok(None) => {
                    // No action was executed (queue empty or state not ready)
                    break;
                }
                Err(err) => {
                    eprintln!("Orchestrator execution failed: {err:?}");
                    break;
                }
            }
        }
    }
    
    fn log_trace(&self, entry: TraceEntry) {
        if let Some(logger) = &self.trace_logger {
            if let Err(err) = logger.log(entry) {
                eprintln!("Trace logging failed: {err:?}");
            }
        }
    }

    fn report_artifact_outcome(&self, outcome: ArtifactUpdateOutcome) {
        let rationale = outcome.rationale.trim();
        if outcome.total_patches == 0 {
            if rationale.is_empty() {
                println!("Artifact editor: no changes.");
            } else {
                println!("Artifact editor: no changes ({rationale}).");
            }
            return;
        }

        let applied_summary: Vec<String> = outcome
            .applied
            .iter()
            .map(|path| path.display().to_string())
            .collect();
        let applied_joined = if applied_summary.is_empty() {
            "none".to_string()
        } else {
            applied_summary.join(", ")
        };

        if rationale.is_empty() {
            println!(
                "Artifact editor applied {}/{} patches (updated: {}).",
                outcome.applied.len(),
                outcome.total_patches,
                applied_joined
            );
        } else {
            println!(
                "Artifact editor applied {}/{} patches (updated: {}). {}",
                outcome.applied.len(),
                outcome.total_patches,
                applied_joined,
                rationale
            );
        }

        if !outcome.rejected.is_empty() {
            for rejected in &outcome.rejected {
                eprintln!(
                    "Artifact patch rejected for {}: {} (see {})",
                    rejected.path.display(),
                    rejected.reason,
                    rejected.reject_path.display()
                );
            }
        }

        if outcome.phasing_updated {
            println!("Phasing index refreshed.");
        }
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

struct TranscriptionClient {
    http: HttpClient,
    base_url: String,
    api_key: String,
    language: String,
}

impl TranscriptionClient {
    fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq transcription")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());
        let language =
            std::env::var("GROQ_STT_LANGUAGE").unwrap_or_else(|_| DEFAULT_STT_LANGUAGE.to_string());

        Ok(Self {
            http,
            base_url,
            api_key,
            language,
        })
    }

    fn transcribe(&self, audio_path: &Path) -> Result<String> {
        let audio_bytes = fs::read(audio_path)
            .with_context(|| format!("Failed to read audio file {}", audio_path.display()))?;

        let file_name = audio_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("audio.wav");

        let part = multipart::Part::bytes(audio_bytes)
            .file_name(file_name.to_string())
            .mime_str("audio/wav")
            .context("Failed to prepare audio part for transcription")?;

        let form = multipart::Form::new()
            .text("model", "whisper-large-v3-turbo")
            .text("language", self.language.clone())
            .text("response_format", "json")
            .part("file", part);

        let url = format!(
            "{}/openai/v1/audio/transcriptions",
            self.base_url.trim_end_matches('/')
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
            .multipart(form)
            .send()
            .context("Groq transcription request failed")?;

        let response = response
            .error_for_status()
            .context("Groq transcription returned an error status")?;

        let payload: TranscriptionResponse = response
            .json()
            .context("Failed to parse Groq transcription response")?;

        if payload.text.trim().is_empty() {
            Err(anyhow!("Groq transcription response was empty"))
        } else {
            Ok(payload.text)
        }
    }
}

#[derive(Debug, Deserialize)]
struct TranscriptionResponse {
    text: String,
}

struct AssistantClient {
    http: HttpClient,
    base_url: String,
    api_key: String,
    model: String,
    temperature: f32,
    max_tokens: u32,
}

impl AssistantClient {
    fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq assistant")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());

        let model =
            std::env::var("GROQ_LLM_MODEL").unwrap_or_else(|_| DEFAULT_LLM_MODEL.to_string());

        let temperature = std::env::var("GROQ_LLM_TEMPERATURE")
            .ok()
            .and_then(|val| val.parse::<f32>().ok())
            .unwrap_or(DEFAULT_LLM_TEMPERATURE);

        let max_tokens = std::env::var("GROQ_LLM_MAX_TOKENS")
            .ok()
            .and_then(|val| val.parse::<u32>().ok())
            .unwrap_or(DEFAULT_LLM_MAX_TOKENS);

        Ok(Self {
            http,
            base_url,
            api_key,
            model,
            temperature,
            max_tokens,
        })
    }

    fn reply(&self, transcript: &str) -> Result<String> {
        let body = json!({
            "model": self.model,
            "messages": [
                {"role": "system", "content": SMART_SECRETARY_PROMPT},
                {"role": "user", "content": transcript}
            ],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "stream": false
        });

        let url = format!(
            "{}/openai/v1/chat/completions",
            self.base_url.trim_end_matches('/')
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("Groq assistant request failed")?;

        let response = response
            .error_for_status()
            .context("Groq assistant returned an error status")?;

        let payload: ChatCompletionResponse = response
            .json()
            .context("Failed to parse Groq assistant response")?;

        let message = payload
            .choices
            .into_iter()
            .find_map(|choice| choice.message.content)
            .unwrap_or_default();

        if message.trim().is_empty() {
            Err(anyhow!("Groq assistant response was empty"))
        } else {
            Ok(message)
        }
    }
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatMessage,
}

#[derive(Debug, Deserialize)]
struct ChatMessage {
    content: Option<String>,
}

#[derive(Debug, Clone)]
struct TtsAudio {
    bytes: Vec<u8>,
    content_type: String,
    note: Option<String>,
}

struct TtsClient {
    http: HttpClient,
    base_url: String,
    api_key: String,
    model: String,
    voice: String,
}

impl TtsClient {
    fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq TTS")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());

        let model =
            std::env::var("GROQ_TTS_MODEL").unwrap_or_else(|_| DEFAULT_TTS_MODEL.to_string());

        let voice =
            std::env::var("GROQ_TTS_VOICE").unwrap_or_else(|_| DEFAULT_TTS_VOICE.to_string());

        Ok(Self {
            http,
            base_url,
            api_key,
            model,
            voice,
        })
    }

    fn synthesize(&self, text: &str) -> Result<TtsAudio> {
        if text.trim().is_empty() {
            return Err(anyhow!("TTS input text was empty"));
        }

        let body = json!({
            "model": self.model,
            "voice": self.voice,
            "input": text,
            "response_format": "wav"
        });

        let url = format!(
            "{}/openai/v1/audio/speech",
            self.base_url.trim_end_matches('/')
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("Groq TTS request failed")?;

        let response = response
            .error_for_status()
            .context("Groq TTS returned an error status")?;

        let content_type = response
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|raw| raw.to_str().ok())
            .map(|s| s.to_owned())
            .unwrap_or_default();

        let bytes = response
            .bytes()
            .context("Failed to read Groq TTS payload body")?;

        if bytes.is_empty() {
            return Err(anyhow!("Groq TTS response was empty"));
        }

        if content_type.contains("application/json") || bytes.starts_with(b"{") {
            let payload: Value =
                serde_json::from_slice(&bytes).context("Failed to parse Groq TTS JSON response")?;

            let decoded = extract_audio_bytes(&payload)
                .ok_or_else(|| anyhow!("Groq TTS JSON response missing audio payload"))?;

            if decoded.is_empty() {
                Err(anyhow!(
                    "Groq TTS audio payload was empty after base64 decode"
                ))
            } else {
                let (bytes, repair_note) = maybe_repair_wav(decoded)?;
                Ok(TtsAudio {
                    bytes,
                    content_type: format!("{} (json)", content_type),
                    note: merge_notes(Some("decoded from JSON payload".to_string()), repair_note),
                })
            }
        } else {
            let raw = bytes.to_vec();
            let (bytes, repair_note) = maybe_repair_wav(raw)?;
            Ok(TtsAudio {
                bytes,
                content_type,
                note: repair_note,
            })
        }
    }

    fn voice(&self) -> &str {
        &self.voice
    }
}

struct SpeechPlayer {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

impl SpeechPlayer {
    fn new() -> Result<Self> {
        let (stream, handle) =
            OutputStream::try_default().context("Failed to create TTS output stream")?;
        Ok(Self {
            _stream: stream,
            handle,
        })
    }

    fn play(&self, audio: &TtsAudio) -> Result<()> {
        if audio.bytes.is_empty() {
            return Err(anyhow!("No audio data supplied for playback"));
        }

        let sink = Sink::try_new(&self.handle).context("Failed to create TTS sink")?;
        let cursor = Cursor::new(audio.bytes.clone());
        let mut reader = match AudioReader::new(cursor) {
            Ok(r) => r,
            Err(err) => {
                let dump_path = dump_tts_audio(audio).ok();
                let info = build_tts_error_info("read", audio, dump_path.as_ref());
                return Err(err).context(info);
            }
        };
        let desc = reader.description();
        let channels = u16::try_from(desc.channel_count())
            .map_err(|_| anyhow!("TTS audio channel count exceeds supported range"))?;

        if channels == 0 {
            return Err(anyhow!("TTS audio has zero channels"));
        }

        let sample_rate = desc.sample_rate();
        let samples: Vec<f32> = match reader
            .samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
        {
            Ok(samples) => samples,
            Err(err) => {
                let dump_path = dump_tts_audio(audio).ok();
                let info = build_tts_error_info("decode", audio, dump_path.as_ref());
                return Err(err).context(info);
            }
        };

        let buffer = SamplesBuffer::new(channels, sample_rate, samples);
        sink.append(buffer);
        sink.detach();
        Ok(())
    }
}

#[derive(Serialize)]
struct TraceEntry {
    id: String,
    timestamp: String,
    mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    user_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    assistant_text: Option<String>,
    durations: TraceDurations,
    #[serde(skip_serializing_if = "Option::is_none")]
    tts: Option<TraceTts>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    errors: Vec<String>,
}

impl TraceEntry {
    fn new(mode: &str) -> Self {
        Self {
            id: String::new(),
            timestamp: String::new(),
            mode: mode.to_string(),
            user_text: None,
            assistant_text: None,
            durations: TraceDurations::default(),
            tts: None,
            errors: Vec::new(),
        }
    }
}

#[derive(Serialize, Default)]
struct TraceDurations {
    record_ms: u64,
    stt_ms: u64,
    llm_ms: u64,
    tts_ms: u64,
    speak_ms: u64,
}

#[derive(Serialize)]
struct TraceTts {
    engine: String,
    voice: String,
    content_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<String>,
}

struct TraceLogger {
    enabled: bool,
    base_dir: PathBuf,
    counter: Cell<u64>,
}

impl TraceLogger {
    fn new(enabled: bool) -> Result<Option<Self>> {
        if !enabled {
            return Ok(None);
        }

        let base_dir = PathBuf::from("logs");
        fs::create_dir_all(&base_dir).context("Failed to create logs directory")?;

        Ok(Some(Self {
            enabled,
            base_dir,
            counter: Cell::new(0),
        }))
    }

    fn next_id(&self) -> String {
        let seq = self.counter.get();
        self.counter.set(seq + 1);
        format!("{}-{:04}", Utc::now().format("%Y%m%dT%H%M%S"), seq)
    }

    fn log(&self, mut entry: TraceEntry) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        entry.id = self.next_id();
        entry.timestamp = Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true);
        let date = Local::now().format("%Y%m%d").to_string();
        let path = self.base_dir.join(format!("trace-{date}.jsonl"));
        let json = serde_json::to_string(&entry).context("Failed to serialize trace entry")?;

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .with_context(|| format!("Failed to open trace log file at {}", path.display()))?;
        file.write_all(json.as_bytes())
            .context("Failed to write trace entry")?;
        file.write_all(b"\n")
            .context("Failed to finalize trace entry")?;
        Ok(())
    }
}

fn build_tts_error_info(stage: &str, audio: &TtsAudio, dump_path: Option<&PathBuf>) -> String {
    let content_type = if audio.content_type.is_empty() {
        "<unknown>"
    } else {
        audio.content_type.as_str()
    };
    let mut info = format!(
        "Failed to {} TTS audio stream (content-type: {}, len: {} bytes",
        stage,
        content_type,
        audio.bytes.len()
    );

    if let Some(note) = &audio.note {
        info.push_str(&format!(", note: {}", note));
    }

    let head = audio
        .bytes
        .iter()
        .take(12)
        .map(|b| format!("{:02X}", b))
        .collect::<Vec<_>>()
        .join(" ");
    if !head.is_empty() {
        info.push_str(&format!(", head: {}", head));
    }

    if let Some(path) = dump_path {
        info.push_str(&format!(", dumped to {}", path.display()));
    }

    info.push(')');
    info
}

fn dump_tts_audio(audio: &TtsAudio) -> Result<PathBuf> {
    let dir = Path::new("tts_debug");
    fs::create_dir_all(dir).context("Failed to create tts_debug directory")?;

    let timestamp = Local::now().format("%Y%m%d-%H%M%S%.3f");
    let mut name = format!("tts-{timestamp}");
    if let Some(note) = &audio.note {
        let slug: String = note
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
            .take(24)
            .collect();
        if !slug.is_empty() {
            name.push('-');
            name.push_str(&slug);
        }
    }

    let ext = guess_audio_extension(&audio.bytes, &audio.content_type);
    let path = dir.join(format!("{name}.{ext}"));
    fs::write(&path, &audio.bytes).context("Failed to write TTS debug dump")?;
    Ok(path)
}

fn guess_audio_extension(bytes: &[u8], content_type: &str) -> &'static str {
    if content_type.contains("wav") || bytes.starts_with(b"RIFF") {
        "wav"
    } else if content_type.contains("mp3")
        || content_type.contains("mpeg")
        || bytes.starts_with(b"ID3")
    {
        "mp3"
    } else if content_type.contains("ogg") || bytes.starts_with(b"OggS") {
        "ogg"
    } else {
        "bin"
    }
}

fn maybe_repair_wav(bytes: Vec<u8>) -> Result<(Vec<u8>, Option<String>)> {
    if bytes.len() < 44 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Ok((bytes, None));
    }

    let mut data_found = false;
    let mut note = None;
    let mut repaired = bytes;

    if let Ok(fixed) = u32::try_from(repaired.len().saturating_sub(8)) {
        let current = u32::from_le_bytes(repaired[4..8].try_into().unwrap());
        if current == 0xFFFF_FFFF || current as usize + 8 != repaired.len() {
            repaired[4..8].copy_from_slice(&fixed.to_le_bytes());
            note = Some(format!("patched RIFF size {}->{}", current, fixed));
        }
    }

    let mut offset = 12usize;
    while offset + 8 <= repaired.len() {
        let chunk_id = &repaired[offset..offset + 4];
        let chunk_size = u32::from_le_bytes(repaired[offset + 4..offset + 8].try_into().unwrap());
        let chunk_data_start = offset + 8;
        if chunk_id == b"data" {
            data_found = true;
            let available = repaired.len().saturating_sub(chunk_data_start);
            if chunk_size == 0xFFFF_FFFF || chunk_size as usize > available {
                if let Ok(fixed) = u32::try_from(available) {
                    let old_note = note.take();
                    let mut pieces = vec![format!("patched data size {}->{}", chunk_size, fixed)];
                    if let Some(existing) = old_note {
                        pieces.push(existing);
                    }
                    note = Some(pieces.join(", "));
                    repaired[offset + 4..offset + 8].copy_from_slice(&fixed.to_le_bytes());
                }
            }
            break;
        }

        let mut next = chunk_data_start + chunk_size as usize;
        if chunk_size % 2 == 1 {
            next += 1; // pad byte
        }
        if next <= offset {
            break;
        }
        offset = next;
    }

    if !data_found {
        return Ok((repaired, note));
    }

    Ok((repaired, note))
}

fn merge_notes(lhs: Option<String>, rhs: Option<String>) -> Option<String> {
    match (lhs, rhs) {
        (None, None) => None,
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (Some(a), Some(b)) => Some(format!("{}; {}", a, b)),
    }
}

fn extract_audio_bytes(value: &Value) -> Option<Vec<u8>> {
    fn decode_value(value: &Value) -> Option<Vec<u8>> {
        match value {
            Value::String(s) => decode_base64_candidate(s),
            Value::Array(items) => items.iter().find_map(decode_value),
            Value::Object(map) => {
                for key in ["audio", "data", "audio_base64", "audioContent", "content"] {
                    if let Some(val) = map.get(key) {
                        if let Some(decoded) = decode_value(val) {
                            return Some(decoded);
                        }
                    }
                }
                map.values().find_map(decode_value)
            }
            _ => None,
        }
    }

    decode_value(value)
}

fn decode_base64_candidate(raw: &str) -> Option<Vec<u8>> {
    let cleaned: String = raw.chars().filter(|c| !c.is_whitespace()).collect();
    if cleaned.is_empty() {
        return None;
    }

    STANDARD
        .decode(cleaned.as_bytes())
        .ok()
        .or_else(|| URL_SAFE.decode(cleaned.as_bytes()).ok())
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
