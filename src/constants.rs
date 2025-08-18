pub const SAMPLE_RATE_44KHZ: u32 = 44100;
pub const SAMPLE_RATE_16KHZ: u32 = 16000;
pub const WAV_BITS_PER_SAMPLE: u16 = 16;
pub const WAV_CHANNELS: u16 = 1;

pub const GROQ_API_ENDPOINT: &str = "https://api.groq.com/openai/v1/audio/transcriptions";
pub const GROQ_MODEL: &str = "whisper-large-v3-turbo";
pub const GROQ_RESPONSE_FORMAT: &str = "json";
pub const GROQ_LANGUAGE: &str = "en";

pub const ENV_FILE_PATH: &str = ".env";
pub const ENV_API_KEY: &str = "GROQ_API_KEY";

pub const POLL_TIMEOUT_MS: u64 = 50;
pub const HOTKEY_TIMEOUT_MS: u64 = 100;

pub const ERROR_DISPLAY_LIMIT: usize = 20;