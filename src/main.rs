use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
    sync::atomic::Ordering,
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use device_query::{DeviceQuery, DeviceState, Keycode};

mod artifacts;
mod audio;
mod io_guard;
pub mod orchestrator;
mod router;
mod services;
mod trace;
mod tts_backend;

use crate::artifacts::{ArtifactManager, ArtifactUpdateOutcome};
use crate::audio::{BeepPlayer, Recorder, SpeechPlayer, save_recording};
use crate::orchestrator::{Action, Orchestrator};
use crate::router::Router;
use crate::services::{AssistantClient, TranscriptionClient};
use crate::trace::{TraceEntry, TraceLogger, TraceTts};
use crate::tts_backend::{LocalTtsBackend, TtsBackend};

pub(crate) const TARGET_SAMPLE_RATE: u32 = 16_000;
pub(crate) const PUSH_TO_TALK_KEY: Keycode = Keycode::Space;
pub(crate) const EXIT_KEY: Keycode = Keycode::Escape;
const OUTPUT_DIR: &str = "recordings";
pub(crate) const DEFAULT_STT_LANGUAGE: &str = "en";
pub(crate) const DEFAULT_LLM_TEMPERATURE: f32 = 0.3;
pub(crate) const DEFAULT_LLM_MAX_TOKENS: u32 = 400;
pub(crate) const DEFAULT_LLM_MODEL: &str = "moonshotai/kimi-k2-instruct-0905";
pub(crate) const SMART_SECRETARY_PROMPT: &str = "You are Walkcoach, a smart secretary. Answer in one to three short sentences. If one clarifier would change the answer, ask it. Otherwise, give tight, actionable guidance. No filler.";

fn main() -> Result<()> {
    let env_source = load_env_file()?;
    ensure_groq_key(env_source.as_deref())?;

    // Set default lighter debug output if not explicitly configured
    if std::env::var("WALKCOACH_DEBUG_ROUTER").is_err() {
        unsafe {
            std::env::set_var("WALKCOACH_DEBUG_ROUTER_LITE", "1");
        }
    }

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
    tts: Box<dyn TtsBackend>,
    trace_logger: Option<TraceLogger>,
    #[allow(dead_code)]
    artifact_manager: Option<ArtifactManager>, // Moved to orchestrator
    orchestrator: Orchestrator,
    router: Router,
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
        // Choose TTS backend - default to local TTS unless explicitly using Groq
        let tts: Box<dyn TtsBackend> = if std::env::var("USE_GROQ_TTS").is_ok() {
            use crate::tts_backend::GroqTtsBackend;
            eprintln!("Using Groq TTS (costs money, higher quality)");
            Box::new(GroqTtsBackend::new(api_key.clone())?)
        } else {
            eprintln!("Using local TTS (free, lower quality)");
            eprintln!("Set USE_GROQ_TTS=1 for higher quality paid TTS");
            Box::new(LocalTtsBackend::new()?)
        };
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

        let router = Router::new()?;

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
            router,
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
                        // More minimal output
                        println!(
                            " {:<80} Saved {} ({reported_duration:.2}s captured, key held for {:.2}s)",
                            "",
                            saved.path.file_name().unwrap_or_default().to_string_lossy(),
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
                trace_entry.durations.record_ms =
                    Some((saved.duration_seconds * 1000.0).round() as u64);

                let stt_start = Instant::now();
                let transcript = match self.transcriber.transcribe(&saved.path) {
                    Ok(transcript) => {
                        trace_entry.durations.stt_ms = Some(stt_start.elapsed().as_millis() as u64);
                        println!("Transcript:  {transcript}");
                        trace_entry.user_text = Some(transcript.clone());
                        transcript
                    }
                    Err(err) => {
                        trace_entry.durations.stt_ms = Some(stt_start.elapsed().as_millis() as u64);
                        let msg = format!("transcription failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("Transcription failed for {}: {err:?}", saved.path.display());
                        self.log_trace(trace_entry);
                        continue;
                    }
                };

                // Use router to determine intent (LLM-based or local yes/no)
                let (answer, skip_artifacts) = match self.router.parse_user_input(&transcript) {
                    Ok(intent) => {
                        // Handle local command directly (no LLM needed)
                        match intent {
                            crate::router::Intent::Directive { ref action } => {
                                // Execute directive immediately
                                let action_clone = action.clone();
                                match self.orchestrator.handle_intent(intent) {
                                    Ok(_) => {
                                        let (msg, skip_tts) = match action_clone {
                                            crate::router::ProposedAction::WriteDescription => {
                                                ("Writing description now...", false)
                                            }
                                            crate::router::ProposedAction::WritePhasing => {
                                                ("Writing phasing now...", false)
                                            }
                                            crate::router::ProposedAction::ReadDescription => {
                                                ("Reading description", true)
                                            } // Skip TTS, file will be spoken
                                            crate::router::ProposedAction::ReadPhasing => {
                                                ("Reading phasing", true)
                                            } // Skip TTS, file will be spoken
                                            crate::router::ProposedAction::Stop => {
                                                ("Stopping", false)
                                            }
                                            crate::router::ProposedAction::RepeatLast => {
                                                ("Repeating", true)
                                            } // Skip TTS, cached content will be spoken
                                            _ => ("Executing...", false),
                                        };
                                        println!("Assistant: {msg}");
                                        trace_entry.assistant_text = Some(msg.to_string());
                                        // Return a special marker to skip TTS if this action will speak its own content
                                        if skip_tts {
                                            ("[SKIP_TTS]".to_string(), true)
                                        } else {
                                            (msg.to_string(), true)
                                        }
                                    }
                                    Err(err) => {
                                        let msg = format!("Failed: {err}");
                                        eprintln!("Intent handling failed: {err:?}");
                                        println!("Assistant: {msg}");
                                        trace_entry.assistant_text = Some(msg.clone());
                                        self.log_trace(trace_entry);
                                        continue;
                                    }
                                }
                            }
                            crate::router::Intent::Confirmation { .. } => {
                                // Handle yes/no
                                match self.orchestrator.handle_intent(intent) {
                                    Ok(response) => {
                                        let msg = if response == "executing" {
                                            "Confirmed, executing now"
                                        } else if response == "cancelled" {
                                            "Cancelled"
                                        } else {
                                            &response
                                        };
                                        println!("Assistant: {msg}");
                                        trace_entry.assistant_text = Some(msg.to_string());
                                        (msg.to_string(), true)
                                    }
                                    Err(err) => {
                                        let _msg = format!("Failed: {err}");
                                        eprintln!("Confirmation failed: {err:?}");
                                        self.log_trace(trace_entry);
                                        continue;
                                    }
                                }
                            }
                            crate::router::Intent::Proposal {
                                action: _,
                                ref question,
                            } => {
                                // Store proposal and ask question
                                let q = question.clone();
                                self.orchestrator.handle_intent(intent).ok();
                                println!("Assistant: {}", q);
                                trace_entry.assistant_text = Some(q.clone());
                                (q, true)
                            }
                            crate::router::Intent::Info { ref message } => {
                                // Info intent means it's conversational - pass to assistant
                                if message == "Got it" {
                                    // This is a generic info response, use the assistant for real conversation
                                    let llm_start = Instant::now();
                                    match self.assistant.reply(&transcript) {
                                        Ok(answer) => {
                                            trace_entry.durations.llm_ms =
                                                Some(llm_start.elapsed().as_millis() as u64);
                                            println!("Assistant: {answer}");
                                            trace_entry.assistant_text = Some(answer.clone());
                                            (answer, false) // Don't skip artifacts
                                        }
                                        Err(err) => {
                                            let msg = format!("Assistant failed: {err}");
                                            eprintln!("{msg}");
                                            (msg, true)
                                        }
                                    }
                                } else {
                                    println!("Assistant: {message}");
                                    trace_entry.assistant_text = Some(message.clone());
                                    (message.clone(), true)
                                }
                            }
                        }
                    }
                    Err(err) => {
                        // Router failed, fall back to regular assistant
                        eprintln!("Router failed: {err:?}");

                        // Need LLM interpretation
                        let llm_start = Instant::now();
                        match self.assistant.reply(&transcript) {
                            Ok(answer) => {
                                trace_entry.durations.llm_ms =
                                    Some(llm_start.elapsed().as_millis() as u64);

                                // Parse assistant response for intent
                                let intent =
                                    self.router.parse_assistant_response(&transcript, &answer);

                                // Handle the intent
                                let response = match &intent {
                                    crate::router::Intent::Proposal {
                                        action: _,
                                        question,
                                    } => {
                                        // Store proposal and return question
                                        let q = question.clone();
                                        self.orchestrator.handle_intent(intent).ok();
                                        q
                                    }
                                    crate::router::Intent::Directive { .. } => {
                                        // LLM suggested a directive, execute it
                                        match self.orchestrator.handle_intent(intent) {
                                            Ok(_) => format!("{} Done.", answer),
                                            Err(err) => {
                                                eprintln!("Intent handling failed: {err:?}");
                                                answer.clone()
                                            }
                                        }
                                    }
                                    crate::router::Intent::Info { message } => {
                                        // Just informational
                                        message.clone()
                                    }
                                    _ => answer.clone(),
                                };

                                println!("Assistant: {response}");
                                trace_entry.assistant_text = Some(response.clone());
                                (response, false)
                            }
                            Err(err) => {
                                trace_entry.durations.llm_ms =
                                    Some(llm_start.elapsed().as_millis() as u64);
                                let msg = format!("assistant failed: {err}");
                                trace_entry.errors.push(msg);
                                eprintln!("Assistant reply failed: {err:?}");
                                self.log_trace(trace_entry);
                                continue;
                            }
                        }
                    }
                };

                // Skip TTS synthesis if the answer is our special marker
                let tts_audio = if answer == "[SKIP_TTS]" {
                    None
                } else {
                    let tts_start = Instant::now();
                    match self.tts.synthesize(&answer) {
                        Ok(audio) => {
                            trace_entry.durations.tts_ms =
                                Some(tts_start.elapsed().as_millis() as u64);
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
                                model: None,
                                voice: self.tts.voice().to_string(),
                                content_type: audio.content_type.clone(),
                                note: audio.note.clone(),
                            });
                            Some(audio)
                        }
                        Err(err) => {
                            trace_entry.durations.tts_ms =
                                Some(tts_start.elapsed().as_millis() as u64);
                            let msg = format!("tts failed: {err}");
                            trace_entry.errors.push(msg);
                            eprintln!("TTS synthesis failed: {err:?}");
                            self.log_trace(trace_entry);
                            continue;
                        }
                    }
                };

                if let Some(audio) = &tts_audio {
                    let speak_start = Instant::now();
                    if let Err(err) = self.speaker.play(audio) {
                        let msg = format!("playback failed: {err}");
                        trace_entry.errors.push(msg);
                        eprintln!("Playback failed: {err:?}");
                    }
                    trace_entry.durations.speak_ms = Some(speak_start.elapsed().as_millis() as u64);
                }

                // Queue artifact processing through orchestrator
                // Skip if this was a direct command that already executed
                if !skip_artifacts {
                    let action = Action::ProcessArtifacts {
                        transcript: transcript.clone(),
                        reply: answer.clone(),
                    };

                    if let Err(err) = self.orchestrator.enqueue(action) {
                        eprintln!("Failed to queue artifact processing: {err:?}");
                    }
                }

                // Add to conversation history if we have both transcript and assistant response
                if let Some(assistant_text) = trace_entry.assistant_text.as_ref() {
                    self.orchestrator
                        .add_to_history(&transcript, assistant_text);
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
        // Clear any lingering interrupt flag before processing
        self.orchestrator.clear_interrupt();

        // Execute actions from the queue (single-threaded, one at a time)
        while self.orchestrator.has_pending() {
            match self.orchestrator.execute_next() {
                Ok(Some(result)) => {
                    // Handle artifact processing outcome
                    if let Some(outcome) = result.artifact_outcome {
                        self.report_artifact_outcome(outcome);
                    }

                    // Speak any text that needs to be spoken
                    if let Some(text) = result.speak_text {
                        // Check for interrupt before speaking
                        if !self.orchestrator.interrupt_handle().load(Ordering::Relaxed) {
                            if let Ok(audio) = self.tts.synthesize(&text) {
                                // For local TTS, the audio has already been spoken during synthesize()
                                // The returned audio is just a placeholder
                                // For Groq TTS, we need to play the actual audio
                                if audio.macos_say_token().is_none() {
                                    // Use interruptible playback with orchestrator's interrupt handle
                                    if let Err(err) = self.speaker.play_interruptible(
                                        &audio,
                                        self.orchestrator.interrupt_handle(),
                                        &self.keyboard,
                                    ) {
                                        eprintln!("Failed to speak: {err:?}");
                                    }
                                }
                            }
                        }
                    }

                    // Speak completion message if present
                    if let Some(msg) = result.completion_message {
                        if !self.orchestrator.interrupt_handle().load(Ordering::Relaxed) {
                            if let Ok(audio) = self.tts.synthesize(&msg) {
                                // Check if local TTS already spoke it
                                if audio.macos_say_token().is_none() {
                                    if let Err(err) = self.speaker.play(&audio) {
                                        eprintln!("Failed to speak completion: {err:?}");
                                    }
                                }
                            }
                        }
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
