import 'dotenv/config';
import { GoogleGenAI, Modality } from '@google/genai';
import fs from 'fs';
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log('🎤 Gemini Live Voice Assistant\n');

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('Error: GEMINI_API_KEY not found in .env');
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey });

// Use half-cascade for reliability or native for best quality
const MODEL_NAME = 'gemini-live-2.5-flash-preview'; // More reliable
// const MODEL_NAME = 'gemini-2.5-flash-native-audio-preview-09-2025'; // Best quality

const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: 'You are a helpful assistant. Be concise and natural.',
  // Direct config fields (not nested)
  temperature: 0.7,
};

console.log('Model:', MODEL_NAME);
console.log('Connecting...\n');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

let session = null;
let recordingProcess = null;
let isProcessing = false;
let responseQueue = [];

function createWavHeader(dataSize, sampleRate, bitsPerSample, channels) {
  const buffer = Buffer.alloc(44);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(dataSize + 36, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * channels * bitsPerSample / 8, 28);
  buffer.writeUInt16LE(channels * bitsPerSample / 8, 32);
  buffer.writeUInt16LE(bitsPerSample, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);
  return buffer;
}

// Stream audio directly to player for lower latency
function streamAudio() {
  // Use sox play command for streaming
  const play = spawn('play', [
    '-t', 'raw',
    '-r', '24000',
    '-b', '16',
    '-e', 'signed-integer',
    '-c', '1',
    '-',  // read from stdin
    '-q'  // quiet mode
  ], { stdio: ['pipe', 'ignore', 'ignore'] });

  play.on('error', (err) => {
    console.error('Playback error:', err.message);
  });

  return play;
}

function recordAudio() {
  return new Promise((resolve, reject) => {
    const tempFile = path.join(__dirname, `.recording_${Date.now()}.raw`);

    console.log('🔴 Recording... (Press ENTER to stop)');

    recordingProcess = spawn('sox', [
      '-d',
      '-r', '16000',
      '-c', '1',
      '-b', '16',
      '-e', 'signed-integer',
      tempFile,
      'trim', '0', '30'
    ], { stdio: ['pipe', 'ignore', 'ignore'] });

    recordingProcess.on('error', (err) => {
      console.error('Recording error:', err.message);
      reject(err);
    });

    process.stdin.setRawMode(true);
    process.stdin.resume();

    const onKeypress = (chunk) => {
      if (chunk.toString() === '\r' || chunk.toString() === '\n') {
        process.stdin.removeListener('data', onKeypress);
        process.stdin.setRawMode(false);
        if (recordingProcess) {
          recordingProcess.kill('SIGTERM');
        }
      }
    };

    process.stdin.on('data', onKeypress);

    recordingProcess.on('close', () => {
      process.stdin.setRawMode(false);

      if (fs.existsSync(tempFile)) {
        const audioBuffer = fs.readFileSync(tempFile);
        fs.unlinkSync(tempFile);
        console.log(`⬜ Recorded ${(audioBuffer.length / 1024).toFixed(1)}KB\n`);
        resolve(audioBuffer);
      } else {
        reject(new Error('No audio recorded'));
      }
    });
  });
}

async function processVoice() {
  if (!session || isProcessing) return;

  isProcessing = true;

  // Clean slate for this turn
  responseQueue = [];

  try {
    const audioBuffer = await recordAudio();

    if (audioBuffer.length < 1600) {
      console.log('Too short, try again\n');
      isProcessing = false;
      return;
    }

    console.log('Processing...\n');
    const audioBase64 = audioBuffer.toString('base64');

    // Send audio and mark end
    await session.sendRealtimeInput({
      audio: {
        data: audioBase64,
        mimeType: 'audio/pcm;rate=16000'
      }
    });
    await session.sendRealtimeInput({ audioStreamEnd: true });

    // Start audio streaming player
    const player = streamAudio();

    let done = false;
    let inputTranscript = '';
    let outputTranscript = '';
    let hasInput = false;
    let hasOutput = false;
    let audioCount = 0;

    const startTime = Date.now();

    // Process until turn complete
    while (!done) {
      if (responseQueue.length > 0) {
        const msg = responseQueue.shift();

        // Input transcription (accumulate all chunks)
        if (msg.serverContent?.inputTranscription?.text) {
          inputTranscript = msg.serverContent.inputTranscription.text;
          if (!hasInput) {
            process.stdout.write('📝 You: ');
            hasInput = true;
          }
          // Update the line with full transcript
          process.stdout.write(`\r📝 You: ${inputTranscript}`);
        }

        // Output transcription (accumulate all chunks)
        if (msg.serverContent?.outputTranscription?.text) {
          if (hasInput && !hasOutput) {
            console.log(''); // New line after input
          }
          if (!hasOutput) {
            process.stdout.write('🤖 Gemini: ');
            hasOutput = true;
          }
          outputTranscript = msg.serverContent.outputTranscription.text;
          // Update the line with full transcript
          process.stdout.write(`\r🤖 Gemini: ${outputTranscript}`);
        }

        // Stream audio chunks directly to player
        if (msg.data && player.stdin && !player.killed) {
          const audioChunk = Buffer.from(msg.data, 'base64');
          player.stdin.write(audioChunk);
          audioCount++;
        }

        // Turn complete - wait for it
        if (msg.serverContent?.turnComplete) {
          done = true;
        }
      }

      // Small delay to prevent busy waiting
      await new Promise(r => setTimeout(r, 10));

      // Safety timeout (very generous)
      if (Date.now() - startTime > 60000) {
        console.log('\n⚠️  Safety timeout (60s)');
        done = true;
      }
    }

    // Close the audio stream
    if (player.stdin && !player.killed) {
      player.stdin.end();
    }

    // Final newline and timing
    if (hasOutput) console.log('');
    console.log(`\n✓ Done (${((Date.now() - startTime) / 1000).toFixed(1)}s, ${audioCount} chunks)\n`);

  } catch (error) {
    console.error('Error:', error.message, '\n');
  } finally {
    isProcessing = false;
    console.log('Ready (press "r" to record):');
  }
}

async function main() {
  try {
    session = await ai.live.connect({
      model: MODEL_NAME,
      config: config,
      callbacks: {
        onmessage: (msg) => {
          responseQueue.push(msg);
        },
        onerror: (error) => {
          console.error('Error:', error?.message || error);
        },
        onclose: () => {
          console.log('Connection closed');
          process.exit(0);
        }
      },
    });

    console.log('✅ Connected!\n');
    console.log('Commands:');
    console.log('  r  = Record voice');
    console.log('  q  = Quit\n');
    console.log('Ready (press "r" to record):');

    rl.on('line', async (line) => {
      const input = line.trim().toLowerCase();

      if (input === 'q' || input === 'quit' || input === 'exit') {
        console.log('\nGoodbye!');
        if (recordingProcess) recordingProcess.kill();
        if (session) await session.close();
        process.exit(0);
      }

      if (input === 'r' || input === 'record') {
        await processVoice();
      }
    });

  } catch (error) {
    console.error('Failed to connect:', error.message);
    process.exit(1);
  }
}

process.on('SIGINT', () => {
  console.log('\n\nGoodbye!');
  if (recordingProcess) recordingProcess.kill();
  process.exit(0);
});

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});