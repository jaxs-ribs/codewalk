# Gemini Live Voice Assistant 🎤

A real-time voice assistant using Google's Gemini Live API with full audio transcription.

## Features

- 🎤 **Voice Input**: Record your voice with push-to-talk
- 🔊 **Voice Output**: Natural audio responses from Gemini
- 📝 **Live Transcription**: See what you said and what Gemini says
- ⚡ **Low Latency**: Optimized for fast responses
- 🌍 **Multi-language**: Supports 24+ languages

## Prerequisites

- Node.js 18+
- macOS/Linux (Windows with WSL)
- `sox` for audio recording:
  ```bash
  # macOS
  brew install sox

  # Linux
  sudo apt-get install sox
  ```

## Setup

1. Clone the repo:
   ```bash
   git clone <repo-url>
   cd gemini-live-mvp
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Add your Gemini API key to `.env`:
   ```bash
   echo "GEMINI_API_KEY=your-key-here" > .env
   ```

   Get your API key from: https://makersuite.google.com/app/apikey

## Usage

```bash
npm start
```

Then:
1. Press `r` to start recording
2. Speak your question
3. Press `ENTER` to stop and send
4. Listen to Gemini's response

## How It Works

- **Model**: `gemini-2.5-flash-native-audio-preview-09-2025` (native audio for natural voice)
- **Audio Format**: 16kHz PCM input, 24kHz PCM output
- **Transcription**: Real-time input and output transcription
- **WebSocket**: Persistent connection for low latency

## Configuration

Edit `app.js` to change:
- **Model**: Switch between native audio and half-cascade models
- **System Prompt**: Customize Gemini's personality
- **Temperature**: Adjust response creativity

## Troubleshooting

- **No audio playback**: Check that `afplay` (macOS) or `play` (Linux) is available
- **Recording fails**: Ensure `sox` is installed and microphone permissions granted
- **Connection errors**: Verify your API key is valid

## License

MIT