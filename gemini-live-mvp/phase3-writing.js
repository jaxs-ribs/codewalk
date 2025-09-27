import 'dotenv/config';
import { GoogleGenAI, Modality } from '@google/genai';
import fs from 'fs';
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create logs directory
const logsDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir);
}

// Ensure artifacts directory exists
const artifactsDir = path.join(__dirname, 'artifacts');
if (!fs.existsSync(artifactsDir)) {
  fs.mkdirSync(artifactsDir);
}

// Create backups directory
const backupsDir = path.join(artifactsDir, 'backups');
if (!fs.existsSync(backupsDir)) {
  fs.mkdirSync(backupsDir);
}

console.log('🎤 WalkCoach Speccer - Phase 3: Artifact Writing');
console.log('   Writes actual markdown files with TTS optimization\n');

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('Error: GEMINI_API_KEY not found in .env');
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey });
const MODEL_NAME = 'gemini-live-2.5-flash-preview';

// Conversation history for context
let conversationHistory = [];

// Atomic file write with backup
function atomicWrite(filePath, content) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const fileName = path.basename(filePath);

  // Create backup if file exists
  if (fs.existsSync(filePath)) {
    const backupPath = path.join(backupsDir, `${fileName}.${timestamp}.backup`);
    fs.copyFileSync(filePath, backupPath);
    console.log(`   📦 Backup created: ${path.basename(backupPath)}`);
  }

  // Write to temp file first
  const tempPath = `${filePath}.tmp`;
  fs.writeFileSync(tempPath, content);

  // Atomic rename
  fs.renameSync(tempPath, filePath);

  console.log(`   ✅ Wrote ${content.length} chars to ${fileName}`);
  return true;
}

// Tool definitions
const tools = [{
  functionDeclarations: [
    {
      name: "write_artifact",
      description: "Write description or phasing markdown",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: {
            type: "STRING",
            enum: ["description", "phasing"],
            description: "Type of artifact to write"
          },
          content: {
            type: "STRING",
            description: "Full markdown content to write"
          }
        },
        required: ["artifact_type", "content"]
      }
    },
    {
      name: "read_artifact",
      description: "Read description, phasing, or specific phase",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: {
            type: "STRING",
            enum: ["description", "phasing", "phase"],
            description: "Type of artifact to read"
          },
          phase_number: {
            type: "INTEGER",
            description: "Phase number if reading specific phase"
          }
        },
        required: ["artifact_type"]
      }
    },
    {
      name: "route_intent",
      description: "Classify user input as directive or conversation",
      parameters: {
        type: "OBJECT",
        properties: {
          intent: {
            type: "STRING",
            enum: ["directive", "conversation"],
            description: "Classification of user input"
          },
          action: {
            type: "STRING",
            description: "Specific action if directive"
          },
          reasoning: {
            type: "STRING",
            description: "Brief explanation of classification"
          }
        },
        required: ["intent", "reasoning"]
      }
    }
  ]
}];

// Combined system prompt with router, conversation, and generation rules
const SYSTEM_PROMPT = `You are WalkCoach, a voice-first project speccer.

ROUTING RULES:
- DEFAULT to "conversation" unless there's an EXPLICIT command
- Only classify as "directive" for: "write the description", "write the phasing", "read the description", etc.
- Everything else is CONVERSATION

CONVERSATION BEHAVIOR:
- STATEMENTS → Respond ONLY "Noted"
- QUESTIONS → 2-3 sentence answer
- When gathering context, just acknowledge with "Noted"

DESCRIPTION GENERATION RULES:
When writing a description, generate 1500-2500 CHARACTER markdown that:
- Uses flowing prose perfect for text-to-speech
- NO bullet points, NO lists
- Uses contractions (it's, you'll, we're)
- Writes like explaining to a friend on a walk
- Reviews ENTIRE conversation history to capture all mentioned features
- Format: # Project Description\\n\\n[Natural flowing paragraphs]

PHASING GENERATION RULES:
When writing phasing, generate 3-5 phases where each phase:
- Is ONE flowing paragraph (200-400 chars)
- MUST end with "When this phase is done, you'll be able to..."
- NO bullets, NO numbered lists in the content
- Format: ## Phase N: [Title]\\n\\n[Flowing paragraph ending with deliverable]

IMPORTANT: Always use the route_intent tool first to classify input.
When a directive is detected and you need to write, use the write_artifact tool.`;

const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: SYSTEM_PROMPT,
  temperature: 0.7,
  tools
};

console.log('Model:', MODEL_NAME);
console.log('Artifacts directory:', artifactsDir);
console.log('Connecting...\n');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

let session = null;
let recordingProcess = null;
let isProcessing = false;
let responseQueue = [];

// Orchestrator state
let ioGuard = false;

// Stream audio
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

// Handle tool calls - Phase 3: Actually write files
async function handleToolCall(toolCall) {
  const functionResponses = [];

  for (const fc of toolCall.functionCalls) {
    console.log('\n' + '='.repeat(60));
    console.log('🔧 TOOL CALL: ' + fc.name);
    console.log('='.repeat(60));

    if (fc.name === "route_intent") {
      const { intent, action, reasoning } = fc.args || {};
      console.log(`\n📍 Intent: ${intent}`);
      if (action) console.log(`📍 Action: ${action}`);

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: { success: true, intent, action, reasoning }
      });
    }

    else if (fc.name === "write_artifact") {
      const { artifact_type, content } = fc.args || {};

      // Check IoGuard
      if (ioGuard) {
        console.log(`\n⚠️  IoGuard active - queueing write operation`);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { success: false, error: "Another operation in progress" }
        });
        continue;
      }

      // Set IoGuard
      ioGuard = true;
      console.log(`\n📝 Writing ${artifact_type}...`);

      try {
        const filePath = path.join(artifactsDir, `${artifact_type}.md`);
        atomicWrite(filePath, content);

        console.log(`\n📄 Preview of ${artifact_type}:`);
        console.log('─'.repeat(40));
        console.log(content.substring(0, 200) + '...');
        console.log('─'.repeat(40));

        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: {
            success: true,
            message: `Wrote ${artifact_type} (${content.length} chars)`,
            path: filePath
          }
        });
      } catch (error) {
        console.error(`\n❌ Write failed: ${error.message}`);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { success: false, error: error.message }
        });
      } finally {
        // Release IoGuard
        ioGuard = false;
      }
    }

    else if (fc.name === "read_artifact") {
      const { artifact_type, phase_number } = fc.args || {};

      try {
        const filePath = path.join(artifactsDir, `${artifact_type}.md`);

        if (fs.existsSync(filePath)) {
          const content = fs.readFileSync(filePath, 'utf-8');
          console.log(`\n📖 Read ${artifact_type} (${content.length} chars)`);

          functionResponses.push({
            id: fc.id,
            name: fc.name,
            response: {
              success: true,
              content,
              artifact_type
            }
          });
        } else {
          console.log(`\n⚠️  ${artifact_type}.md not found`);
          functionResponses.push({
            id: fc.id,
            name: fc.name,
            response: {
              success: false,
              error: `${artifact_type}.md does not exist yet`
            }
          });
        }
      } catch (error) {
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { success: false, error: error.message }
        });
      }
    }

    console.log('='.repeat(60));
  }

  if (functionResponses.length > 0) {
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

    // Turn state
    let turnState = {
      inputTranscript: '',
      outputTranscript: '',
      toolCallCount: 0,
      wroteArtifact: false
    };

    let done = false;
    const startTime = Date.now();

    while (!done) {
      if (responseQueue.length > 0) {
        const msg = responseQueue.shift();

        // Handle tool calls
        if (msg.toolCall) {
          turnState.toolCallCount++;

          // Check for write operations
          const writeCall = msg.toolCall.functionCalls?.find(fc => fc.name === 'write_artifact');
          if (writeCall) {
            turnState.wroteArtifact = true;
          }

          await handleToolCall(msg.toolCall);
          continue;
        }

        // Skip code execution
        if (msg.serverContent?.modelTurn?.parts?.some(p => p.executableCode || p.codeExecutionResult)) {
          continue;
        }

        // Input transcript
        if (msg.serverContent?.inputTranscription?.text != null) {
          turnState.inputTranscript = msg.serverContent.inputTranscription.text;
        }

        // Output transcript accumulation
        if (msg.serverContent?.outputTranscription?.text != null) {
          const fragment = msg.serverContent.outputTranscription.text;
          const prevTranscript = turnState.outputTranscript;

          if (fragment.startsWith(prevTranscript)) {
            turnState.outputTranscript = fragment;
          } else if (prevTranscript.length === 0) {
            turnState.outputTranscript = fragment;
          } else {
            turnState.outputTranscript += fragment;
          }
        }

        // Stream audio
        if (msg.data && player.stdin && !player.killed) {
          const audioChunk = Buffer.from(msg.data, 'base64');
          player.stdin.write(audioChunk);
        }

        // Turn complete
        if (msg.serverContent?.turnComplete) {
          while (responseQueue.length > 0) {
            const finalMsg = responseQueue.shift();
            if (finalMsg.serverContent?.outputTranscription?.text != null) {
              const finalText = finalMsg.serverContent.outputTranscription.text;
              if (finalText.startsWith(turnState.outputTranscript)) {
                turnState.outputTranscript = finalText;
              } else {
                turnState.outputTranscript += finalText;
              }
            }
          }
          await new Promise(r => setTimeout(r, 100));
          done = true;
        }
      }

      await new Promise(r => setTimeout(r, 10));

      if (Date.now() - startTime > 90000) {
        console.log('\n⚠️  Timeout');
        done = true;
      }
    }

    if (player.stdin && !player.killed) {
      player.stdin.end();
    }

    // Add to conversation history
    if (turnState.inputTranscript) {
      conversationHistory.push({
        role: 'user',
        text: turnState.inputTranscript
      });
    }

    if (turnState.outputTranscript) {
      conversationHistory.push({
        role: 'assistant',
        text: turnState.outputTranscript
      });
    }

    // Print summary
    console.log('\n' + '='.repeat(60));
    console.log('TURN COMPLETE:');
    console.log(`📝 You: "${turnState.inputTranscript}"`);
    console.log(`🤖 Gemini: "${turnState.outputTranscript}"`);

    if (turnState.wroteArtifact) {
      console.log(`\n✅ Artifact written to disk!`);
    }

    console.log('='.repeat(60));
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
    console.log('🧪 PHASE 3 TEST - Artifact Writing');
    console.log('─'.repeat(55));
    console.log('Instructions:');
    console.log('1. Share some project ideas (gets "Noted" responses)');
    console.log('2. Say "Write the description" to generate artifact');
    console.log('3. Check artifacts/ folder for description.md');
    console.log('4. Say "Write the phasing" to generate phases');
    console.log('');
    console.log('The system will:');
    console.log('  • Synthesize entire conversation into artifacts');
    console.log('  • Write TTS-optimized markdown (no bullets)');
    console.log('  • Create timestamped backups');
    console.log('─'.repeat(55));
    console.log('\nCommands:');
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