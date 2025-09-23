use anyhow::{Context, Result, anyhow};
use once_cell::sync::Lazy;
use reqwest::blocking::Client as HttpClient;
use serde_json::json;
use std::io::Cursor;
#[cfg(target_os = "macos")]
use std::process::Child;
use std::sync::Mutex;
#[cfg(target_os = "macos")]
use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
use std::time::Duration;
#[cfg(not(target_os = "macos"))]
use tts::Tts as LocalTts;

#[cfg(target_os = "macos")]
struct SayProcess {
    token: u64,
    child: Child,
}

#[cfg(target_os = "macos")]
static NEXT_SAY_TOKEN: AtomicU64 = AtomicU64::new(1);

#[cfg(target_os = "macos")]
static SAY_PROCESS: Lazy<Mutex<Option<SayProcess>>> = Lazy::new(|| Mutex::new(None));

#[cfg(target_os = "macos")]
const MACOS_SAY_NOTE_PREFIX: &str = "macos-say";

#[cfg(target_os = "macos")]
pub(crate) fn macos_say_note(token: u64) -> String {
    format!("{}:{}", MACOS_SAY_NOTE_PREFIX, token)
}

#[cfg(target_os = "macos")]
pub(crate) fn stop_say_process(token: Option<u64>) -> bool {
    if let Ok(mut guard) = SAY_PROCESS.lock() {
        if let Some(mut process) = guard.take() {
            if token.map(|t| t == process.token).unwrap_or(true) {
                let _ = process.child.kill();
                let _ = process.child.wait();
                return true;
            } else {
                *guard = Some(process);
            }
        }
    }
    false
}

#[cfg(target_os = "macos")]
pub(crate) fn is_say_process_active(token: u64) -> bool {
    if let Ok(mut guard) = SAY_PROCESS.lock() {
        if let Some(process) = guard.as_mut() {
            if process.token != token {
                return false;
            }
            match process.child.try_wait() {
                Ok(Some(_status)) => {
                    guard.take();
                    false
                }
                Ok(None) => true,
                Err(_) => {
                    guard.take();
                    false
                }
            }
        } else {
            false
        }
    } else {
        false
    }
}

#[cfg(target_os = "macos")]
pub(crate) fn mark_say_process(child: Child) -> u64 {
    let token = NEXT_SAY_TOKEN.fetch_add(1, AtomicOrdering::SeqCst);
    if let Ok(mut guard) = SAY_PROCESS.lock() {
        if let Some(mut existing) = guard.take() {
            let _ = existing.child.kill();
            let _ = existing.child.wait();
        }
        *guard = Some(SayProcess { token, child });
    }
    token
}

#[cfg(target_os = "macos")]
pub(crate) fn parse_say_token(note: &Option<String>) -> Option<u64> {
    note.as_ref()
        .and_then(|value| value.strip_prefix(MACOS_SAY_NOTE_PREFIX))
        .and_then(|suffix| suffix.strip_prefix(':'))
        .and_then(|suffix| suffix.parse::<u64>().ok())
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn stop_say_process(_token: Option<u64>) -> bool {
    false
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn is_say_process_active(_token: u64) -> bool {
    false
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn parse_say_token(_note: &Option<String>) -> Option<u64> {
    None
}

/// Audio data from TTS
#[derive(Debug, Clone)]
pub struct TtsAudio {
    pub bytes: Vec<u8>,
    pub content_type: String,
    pub note: Option<String>,
}

impl TtsAudio {
    pub fn macos_say_token(&self) -> Option<u64> {
        parse_say_token(&self.note)
    }
}

/// Trait for TTS backends
pub trait TtsBackend: Send + Sync {
    fn synthesize(&self, text: &str) -> Result<TtsAudio>;
    fn voice(&self) -> &str;
}

/// Local TTS implementation using system voices
pub struct LocalTtsBackend {
    voice_name: String,
}

impl LocalTtsBackend {
    pub fn new() -> Result<Self> {
        Ok(Self {
            voice_name: "Local Voice".to_string(),
        })
    }
}

impl TtsBackend for LocalTtsBackend {
    fn synthesize(&self, text: &str) -> Result<TtsAudio> {
        if text.trim().is_empty() {
            return Err(anyhow!("TTS input text was empty"));
        }

        // On macOS, use the `say` command directly since tts crate doesn't work properly
        #[cfg(target_os = "macos")]
        {
            use std::process::Command;

            eprintln!(
                "[Local TTS] Speaking via macOS say: {:?}...",
                &text.chars().take(50).collect::<String>()
            );

            let child = Command::new("/usr/bin/say")
                .arg("-r")
                .arg("200")
                .arg(text)
                .spawn()
                .context("Failed to spawn macOS say command")?;

            let token = mark_say_process(child);

            // Return a tiny placeholder since audio is handled by the OS
            let wav_data = create_minimal_wav()?;

            return Ok(TtsAudio {
                bytes: wav_data,
                content_type: "audio/wav".to_string(),
                note: Some(macos_say_note(token)),
            });
        }

        // On other platforms, try to use the tts crate
        #[cfg(not(target_os = "macos"))]
        {
            let mut tts = LocalTts::default()
                .map_err(|e| anyhow!("Failed to initialize local TTS: {}", e))?;

            // Set faster speech rate for development
            if let Ok(current_rate) = tts.get_rate() {
                let faster_rate = (current_rate * 1.5).min(tts.max_rate());
                let _ = tts.set_rate(faster_rate);
            }

            // Speak synchronously (blocking) - this actually produces the sound!
            eprintln!(
                "[Local TTS] Speaking: {:?}...",
                &text.chars().take(50).collect::<String>()
            );
            tts.speak(text, true) // true = blocking, waits for speech to complete
                .map_err(|e| anyhow!("Failed to speak text: {}", e))?;

            // Return a tiny placeholder since the audio already played
            let wav_data = create_minimal_wav()?;

            Ok(TtsAudio {
                bytes: wav_data,
                content_type: "audio/wav".to_string(),
                note: Some("Local TTS (already spoken via system)".to_string()),
            })
        }
    }

    fn voice(&self) -> &str {
        &self.voice_name
    }
}

/// Create a minimal valid WAV file (just a click)
fn create_minimal_wav() -> Result<Vec<u8>> {
    use hound::{SampleFormat, WavWriter};

    let mut cursor = Cursor::new(Vec::new());
    {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 16000,
            bits_per_sample: 16,
            sample_format: SampleFormat::Int,
        };

        let mut writer =
            WavWriter::new(&mut cursor, spec).context("Failed to create WAV writer")?;

        // Just 10ms of silence (160 samples at 16kHz)
        for _ in 0..160 {
            writer
                .write_sample(0i16)
                .context("Failed to write sample")?;
        }

        writer.finalize().context("Failed to finalize WAV")?;
    }

    Ok(cursor.into_inner())
}

/// Groq TTS backend implementation
pub struct GroqTtsBackend {
    http: HttpClient,
    base_url: String,
    api_key: String,
    model: String,
    voice: String,
}

impl GroqTtsBackend {
    pub fn new(api_key: String) -> Result<Self> {
        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for Groq TTS")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());

        let model = std::env::var("GROQ_TTS_MODEL").unwrap_or_else(|_| "playai-tts".to_string());

        let voice = std::env::var("GROQ_TTS_VOICE").unwrap_or_else(|_| "Fritz-PlayAI".to_string());

        Ok(Self {
            http,
            base_url,
            api_key,
            model,
            voice,
        })
    }
}

impl TtsBackend for GroqTtsBackend {
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
            .get("content-type")
            .and_then(|raw| raw.to_str().ok())
            .map(|s| s.to_owned())
            .unwrap_or_default();

        let bytes = response
            .bytes()
            .context("Failed to read Groq TTS payload body")?;

        if bytes.is_empty() {
            return Err(anyhow!("Groq TTS response was empty"));
        }

        // Check if it's an error response
        if content_type.contains("application/json") || bytes.starts_with(b"{") {
            let payload: serde_json::Value = serde_json::from_slice(&bytes)
                .context("Failed to parse Groq TTS error response")?;

            let error_msg = payload["error"]["message"]
                .as_str()
                .unwrap_or("Unknown TTS error");

            return Err(anyhow!("Groq TTS error: {}", error_msg));
        }

        Ok(TtsAudio {
            bytes: bytes.to_vec(),
            content_type,
            note: Some(format!("Groq TTS ({})", self.voice)),
        })
    }

    fn voice(&self) -> &str {
        &self.voice
    }
}
