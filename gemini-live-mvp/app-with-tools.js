import 'dotenv/config';
import { GoogleGenAI, Modality } from '@google/genai';
import fs from 'fs';
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log('🎤 Gemini Live Voice Assistant with Tools\n');

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('Error: GEMINI_API_KEY not found in .env');
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey });

// MUST use half-cascade for tool support (native audio doesn't support tools yet)
const MODEL_NAME = 'gemini-live-2.5-flash-preview';

// Define the write_markdown tool
const writeArtifact = {
  name: "write_markdown",
  description: "Write or append a markdown artifact to disk",
  parameters: {
    type: "OBJECT",
    properties: {
      path: {
        type: "STRING",
        description: "Relative file path, e.g. artifacts/description.md"
      },
      content: {
        type: "STRING",
        description: "Markdown content to write"
      },
      mode: {
        type: "STRING",
        enum: ["append", "overwrite"],
        description: "Write mode"
      }
    },
    required: ["path", "content"]
  }
};

// Define the read_markdown tool
const readArtifact = {
  name: "read_markdown",
  description: "Read a markdown artifact from disk",
  parameters: {
    type: "OBJECT",
    properties: {
      path: {
        type: "STRING",
        description: "Relative file path to read"
      }
    },
    required: ["path"]
  }
};

// Tools array for config
const tools = [{
  functionDeclarations: [writeArtifact, readArtifact]
}];

const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: `You are a senior product spec writer and walking companion.
When the user asks you to write something down, use the write_markdown tool to save it.
When asked to read something back, use read_markdown.
Keep artifacts in the 'artifacts' folder.
Be concise in speech but thorough in written artifacts.`,
  temperature: 0.7,
  tools  // Add tools to config
};

console.log('Model:', MODEL_NAME);
console.log('Tools: write_markdown, read_markdown');
console.log('Connecting...\n');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

let session = null;
let recordingProcess = null;
let isProcessing = false;
let responseQueue = [];

// Ensure artifacts directory exists
const artifactsDir = path.join(__dirname, 'artifacts');
if (!fs.existsSync(artifactsDir)) {
  fs.mkdirSync(artifactsDir);
  console.log('Created artifacts/ directory\n');
}

// Stream audio directly to player
function streamAudio() {
  const play = spawn('play', [
    '-t', 'raw',
    '-r', '24000',
    '-b', '16',
    '-e', 'signed-integer',
    '-c', '1',
    '-',
    '-q'
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

// Handle tool calls
async function handleToolCall(toolCall) {
  const functionResponses = [];

  for (const fc of toolCall.functionCalls) {
    console.log(`\n📝 Tool call: ${fc.name}`);

    if (fc.name === "write_markdown") {
      try {
        const { path: relPath, content, mode = "append" } = fc.args || {};
        const absPath = path.join(__dirname, relPath);

        // Ensure parent directory exists
        const dir = path.dirname(absPath);
        if (!fs.existsSync(dir)) {
          fs.mkdirSync(dir, { recursive: true });
        }

        // Write or append
        if (mode === "overwrite") {
          fs.writeFileSync(absPath, content);
          console.log(`   ✓ Wrote ${Buffer.byteLength(content)} bytes to ${relPath}`);
        } else {
          fs.appendFileSync(absPath, content + "\n\n");
          console.log(`   ✓ Appended ${Buffer.byteLength(content)} bytes to ${relPath}`);
        }

        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: {
            ok: true,
            bytes: Buffer.byteLength(content),
            path: relPath,
            mode
          }
        });
      } catch (e) {
        console.error(`   ✗ Error: ${e.message}`);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { ok: false, error: String(e) }
        });
      }
    }

    if (fc.name === "read_markdown") {
      try {
        const { path: relPath } = fc.args || {};
        const absPath = path.join(__dirname, relPath);

        if (fs.existsSync(absPath)) {
          const content = fs.readFileSync(absPath, 'utf-8');
          console.log(`   ✓ Read ${content.length} chars from ${relPath}`);

          functionResponses.push({
            id: fc.id,
            name: fc.name,
            response: {
              ok: true,
              content,
              path: relPath
            }
          });
        } else {
          throw new Error(`File not found: ${relPath}`);
        }
      } catch (e) {
        console.error(`   ✗ Error: ${e.message}`);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { ok: false, error: String(e) }
        });
      }
    }
  }

  // Send tool responses back
  if (functionResponses.length > 0) {
    console.log('   → Sending tool responses...\n');
    await session.sendToolResponse({ functionResponses });
  }
}

async function processVoice() {
  if (!session || isProcessing) return;

  isProcessing = true;
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

    await session.sendRealtimeInput({
      audio: {
        data: audioBase64,
        mimeType: 'audio/pcm;rate=16000'
      }
    });
    await session.sendRealtimeInput({ audioStreamEnd: true });

    const player = streamAudio();

    let done = false;
    let inputTranscript = '';
    let outputTranscript = '';
    let hasInput = false;
    let hasOutput = false;
    let audioCount = 0;

    const startTime = Date.now();

    while (!done) {
      if (responseQueue.length > 0) {
        const msg = responseQueue.shift();

        // Handle tool calls
        if (msg.toolCall) {
          await handleToolCall(msg.toolCall);
          // Continue processing after tool response
          continue;
        }

        // Input transcription
        if (msg.serverContent?.inputTranscription?.text) {
          inputTranscript = msg.serverContent.inputTranscription.text;
          if (!hasInput) {
            process.stdout.write('📝 You: ');
            hasInput = true;
          }
          process.stdout.write(`\r📝 You: ${inputTranscript}`);
        }

        // Output transcription
        if (msg.serverContent?.outputTranscription?.text) {
          if (hasInput && !hasOutput) {
            console.log('');
          }
          if (!hasOutput) {
            process.stdout.write('🤖 Gemini: ');
            hasOutput = true;
          }
          outputTranscript = msg.serverContent.outputTranscription.text;
          process.stdout.write(`\r🤖 Gemini: ${outputTranscript}`);
        }

        // Stream audio
        if (msg.data && player.stdin && !player.killed) {
          const audioChunk = Buffer.from(msg.data, 'base64');
          player.stdin.write(audioChunk);
          audioCount++;
        }

        // Turn complete
        if (msg.serverContent?.turnComplete) {
          done = true;
        }
      }

      await new Promise(r => setTimeout(r, 10));

      if (Date.now() - startTime > 60000) {
        console.log('\n⚠️  Safety timeout (60s)');
        done = true;
      }
    }

    if (player.stdin && !player.killed) {
      player.stdin.end();
    }

    if (hasOutput) console.log('');
    console.log(`\n✓ Done (${((Date.now() - startTime) / 1000).toFixed(1)}s)\n`);

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
    console.log('Example commands to try:');
    console.log('  • "Write a description for a snake game"');
    console.log('  • "Save the project phases"');
    console.log('  • "Read back what you wrote"');
    console.log('');
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