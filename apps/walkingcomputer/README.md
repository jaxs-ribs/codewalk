# Walking Computer

A voice-first iOS app that turns your phone into a walking computer. Talk to it while you walk - it transcribes, thinks, and speaks back. Built for project planning and documentation on the go.

## What It Does

Hold the button, speak your thoughts, release. The app transcribes your voice (Groq or Avalon), routes it through an AI assistant (Groq Kimi), and responds with synthesized speech. It manages two key artifacts:
- **Description**: Your project pitch in plain English
- **Phasing**: Numbered phases with talk tracks

Commands like "write the description" or "edit phase 2" work instantly. Everything is voice-first, single-threaded, and predictable.

## Setup

1. Add API keys to `.env`:
```
GROQ_API_KEY=your_groq_key
AVALON_API_KEY=your_avalon_key  # optional
ELEVENLABS_API_KEY=your_elevenlabs_key  # optional
```

2. Build and run:
```bash
./run-sim.sh                    # Groq STT + iOS TTS
./run-sim.sh --avalon-stt       # Avalon STT + iOS TTS
./run-sim.sh --elevenlabs       # Groq STT + ElevenLabs TTS
./run-sim.sh --avalon-stt --elevenlabs  # Both alternatives
```

## Avalon STT Integration

The app uses multipart form data to call Avalon's API. In JS/Node you'd do:
```javascript
const formData = new FormData();
formData.append('file', audioBlob, 'audio.mp3');
formData.append('model', 'avalon-v1-en');

fetch('https://api.aquavoice.com/api/v1/audio/transcriptions', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${API_KEY}` },
  body: formData
});
```

Swift's approach is similar but more verbose with manual boundary construction.

## Features

- **Voice-first**: Everything happens through speech
- **Single-threaded**: One action at a time, no surprises
- **Clean logs**: Colored, timestamped, informative
- **Multiple providers**: Swap STT/TTS providers via flags
- **Artifact management**: Read/write project specs by voice

The UI shows a pulsing circle that responds to your voice. Tap or hold to record, watch it transcribe, hear it think.