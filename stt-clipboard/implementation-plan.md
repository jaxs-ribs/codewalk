# STT Clipboard Detector - Implementation Plan

## Overview
Simple voice-to-clipboard tool using Groq Whisper API. Hold key to record, release to transcribe and copy to clipboard.

## Substeps for Implementation

### 1. Core Audio Recording
- Use `cpal` for cross-platform audio capture
- Buffer audio samples while key is held
- Convert to WAV format (16kHz, mono, 16-bit PCM) for Groq Whisper

### 2. Groq Whisper Integration
- **API Endpoint**: `https://api.groq.com/openai/v1/audio/transcriptions`
- **Required Headers**:
  - `Authorization: Bearer {GROQ_API_KEY}`
- **Request Format**: multipart/form-data with:
  - `file`: WAV audio data
  - `model`: "whisper-large-v3-turbo" (fastest, good quality)
  - `response_format`: "json"
  - `language`: "en" (optional, for speed)

### 3. Clipboard Integration
- Use `arboard` crate for cross-platform clipboard access
- Copy transcribed text immediately after receiving response
- Show minimal feedback (e.g., "✓ Copied" in terminal)

### 4. Minimal UI
- Terminal-based initially
- Single key binding (Space or configurable)
- Visual indicator when recording (e.g., "● Recording...")
- Display transcribed text briefly before copying

### 5. Configuration
- `.env` file support:
  ```
  GROQ_API_KEY=your_key_here
  RECORD_KEY=space  # optional, default to space
  ```

## Technical Architecture

```
main.rs
├── audio.rs      # Audio recording with cpal
├── groq.rs       # Groq Whisper API client
├── clipboard.rs  # Clipboard operations
└── config.rs     # Environment loading
```

## Dependencies (Cargo.toml)
```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
cpal = "0.15"
hound = "3.5"  # WAV file creation
reqwest = { version = "0.12", features = ["multipart", "stream"] }
arboard = "3.4"
crossterm = "0.28"
anyhow = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
```

## MVP Features
- Hold Space → record
- Release → transcribe → copy to clipboard
- Show transcribed text briefly
- Minimal error handling (print to stderr)

## Non-goals for MVP
- No GUI
- No TTS
- No LLM integration
- No history/persistence
- No advanced audio processing