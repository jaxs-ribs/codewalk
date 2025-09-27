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

// Create session log file
const sessionId = new Date().toISOString().replace(/[:.]/g, '-');
const logFile = path.join(logsDir, `session_${sessionId}.log`);
const transcriptFile = path.join(logsDir, `transcript_${sessionId}.txt`);

// Logging functions
function log(message, data = null) {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    message,
    data
  };

  // Write to file
  fs.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');

  // Also console log important messages
  if (message.includes('TRANSCRIPT') || message.includes('ERROR')) {
    console.log(`[${timestamp}] ${message}`);
    if (data && typeof data === 'object') {
      console.log(JSON.stringify(data, null, 2));
    }
  }
}

function logTranscript(type, text) {
  const timestamp = new Date().toISOString();
  const entry = `[${timestamp}] ${type}: ${text}\n`;
  fs.appendFileSync(transcriptFile, entry);
}

console.log('🎤 WalkCoach Speccer - Phase 1: Tool Infrastructure');
console.log('   (Testing tool calls only - not writing files yet)');
console.log(`📝 Logs: ${logFile}`);
console.log(`📝 Transcripts: ${transcriptFile}\n`);

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('Error: GEMINI_API_KEY not found in .env');
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey });

// MUST use half-cascade for tool support
const MODEL_NAME = 'gemini-live-2.5-flash-preview';

// Tool definitions matching WalkCoach ProposedActions
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
            description: "Specific action if directive (e.g., write_description, read_phasing)"
          },
          reasoning: {
            type: "STRING",
            description: "Brief explanation of classification"
          }
        },
        required: ["intent"]
      }
    }
  ]
}];

// Simple system prompt for Phase 1 testing
const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: `You are WalkCoach, a voice-first project speccer.

IMPORTANT: Never write or execute code. Only use the provided tools.

Phase 1 Testing Instructions:
- When asked to "write" something, use the write_artifact tool
- When asked to "read" something, use the read_artifact tool
- Use route_intent to classify whether input is a command or conversation
- Keep responses brief and natural
- DO NOT generate code snippets or try to execute code`,
  temperature: 0.7,
  tools
};

console.log('Model:', MODEL_NAME);
console.log('Tools: write_artifact, read_artifact, route_intent');
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

    // Clean recording at 16kHz for Gemini
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

// Handle tool calls - Phase 1: Just log what would happen
async function handleToolCall(toolCall) {
  const functionResponses = [];

  console.log('\n' + '='.repeat(60));
  console.log('🔧 TOOL CALL DETECTED');
  console.log('='.repeat(60));

  for (const fc of toolCall.functionCalls) {
    console.log(`\nTool: ${fc.name}`);
    console.log('Parameters:', JSON.stringify(fc.args, null, 2));

    // For Phase 1, we just acknowledge the tool call without full implementation
    if (fc.name === "write_artifact") {
      const { artifact_type, content } = fc.args || {};
      console.log(`\n→ Would write ${artifact_type} with ${content?.length || 0} characters`);
      if (content && content.length > 0) {
        console.log('→ Content preview:');
        console.log('  ' + content.substring(0, 200).replace(/\n/g, '\n  '));
        if (content.length > 200) console.log('  ...');
      }

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: {
          success: true,
          message: `Test: Would write ${artifact_type}`,
          artifact_type,
          content_preview: content?.substring(0, 100) + "..."
        }
      });
    }

    else if (fc.name === "read_artifact") {
      const { artifact_type, phase_number } = fc.args || {};
      console.log(`\n→ Would read ${artifact_type}${phase_number ? ` phase ${phase_number}` : ''}`);

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: {
          success: true,
          message: `Test: Would read ${artifact_type}`,
          artifact_type,
          phase_number
        }
      });
    }

    else if (fc.name === "route_intent") {
      const { intent, action, reasoning } = fc.args || {};
      console.log(`\n→ Intent: ${intent}`);
      if (action) console.log(`→ Action: ${action}`);
      if (reasoning) console.log(`→ Reasoning: ${reasoning}`);

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: {
          success: true,
          intent,
          action,
          reasoning
        }
      });
    }
  }

  console.log('\n' + '='.repeat(60) + '\n');

  // Send tool responses back
  if (functionResponses.length > 0) {
    console.log('Sending tool responses back to Gemini...\n');
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

    // Turn state tracking per official docs
    let turnState = {
      inputTranscript: '',
      outputTranscript: '',
      toolCallCount: 0,
      audioCount: 0,
      printedInput: false,
      sawGenerationComplete: false
    };

    let done = false;
    const startTime = Date.now();

    console.log('Listening for response...\n');

    while (!done) {
      if (responseQueue.length > 0) {
        const msg = responseQueue.shift();

        // Log EVERY message
        log('MESSAGE_RECEIVED', {
          hasToolCall: !!msg.toolCall,
          hasServerContent: !!msg.serverContent,
          hasData: !!msg.data,
          hasInputTranscript: !!msg.serverContent?.inputTranscription?.text,
          hasOutputTranscript: !!msg.serverContent?.outputTranscription?.text,
          hasTurnComplete: !!msg.serverContent?.turnComplete,
          hasGenerationComplete: !!msg.serverContent?.generationComplete
        });

        // Handle tool calls
        if (msg.toolCall) {
          turnState.toolCallCount++;
          await handleToolCall(msg.toolCall);
          continue;
        }

        // Skip code execution attempts
        if (msg.serverContent?.modelTurn?.parts?.some(p => p.executableCode || p.codeExecutionResult)) {
          continue;
        }

        // Accumulate input transcript (always take latest)
        if (msg.serverContent?.inputTranscription?.text != null) {
          const text = msg.serverContent.inputTranscription.text;
          turnState.inputTranscript = text;
          log('INPUT_TRANSCRIPT', text);
          logTranscript('USER', text);
        }

        // Accumulate output transcript
        if (msg.serverContent?.outputTranscription?.text != null) {
          const fragment = msg.serverContent.outputTranscription.text;
          const prevTranscript = turnState.outputTranscript;
          const prevLength = prevTranscript.length;

          // Better heuristic: if the fragment starts with what we already have,
          // it's a cumulative update. Otherwise, it's likely a continuation.
          if (fragment.startsWith(prevTranscript)) {
            // This is a cumulative update that includes everything so far
            turnState.outputTranscript = fragment;
          } else if (prevLength === 0) {
            // First fragment
            turnState.outputTranscript = fragment;
          } else {
            // This is a continuation fragment, append it
            turnState.outputTranscript += fragment;
          }

          // Log every update
          log('OUTPUT_TRANSCRIPT_UPDATE', {
            prevLength,
            newLength: turnState.outputTranscript.length,
            fragment,
            fullText: turnState.outputTranscript,
            updateType: fragment.startsWith(prevTranscript) ? 'cumulative' : 'append'
          });

          // Always show in console
          console.log(`\n[TRANSCRIPT ${prevLength}→${turnState.outputTranscript.length}] ${turnState.outputTranscript}`);

          // Update transcript file
          logTranscript('GEMINI_UPDATE', turnState.outputTranscript);
        }

        // Stream audio
        if (msg.data && player.stdin && !player.killed) {
          const audioChunk = Buffer.from(msg.data, 'base64');
          player.stdin.write(audioChunk);
          turnState.audioCount++;
        }

        // Generation complete (model done generating, but may still be streaming)
        if (msg.serverContent?.generationComplete) {
          turnState.sawGenerationComplete = true;
        }

        // Turn complete - THE authoritative signal per docs
        if (msg.serverContent?.turnComplete) {
          log('TURN_COMPLETE', { queueLength: responseQueue.length });

          // Process any remaining messages in queue first
          while (responseQueue.length > 0) {
            const finalMsg = responseQueue.shift();
            log('PROCESSING_FINAL_MESSAGE', { hasOutputTranscript: !!finalMsg.serverContent?.outputTranscription?.text });

            if (finalMsg.serverContent?.outputTranscription?.text != null) {
              const finalText = finalMsg.serverContent.outputTranscription.text;
              turnState.outputTranscript = finalText;
              log('FINAL_TRANSCRIPT_UPDATE', finalText);
              console.log(`\n[FINAL TRANSCRIPT] ${finalText}`);
              logTranscript('GEMINI_FINAL', finalText);
            }
          }

          // Small delay to ensure all messages are processed
          await new Promise(r => setTimeout(r, 500));
          done = true;
        }
      }

      await new Promise(r => setTimeout(r, 10));

      // Very generous timeout (90s) - we rely on turnComplete
      if (Date.now() - startTime > 90000) {
        console.log('\n⚠️  Safety timeout (90s) - did not receive turnComplete');
        done = true;
      }
    }

    if (player.stdin && !player.killed) {
      player.stdin.end();
    }

    // Log final state
    log('FINAL_TURN_STATE', {
      inputLength: turnState.inputTranscript.length,
      outputLength: turnState.outputTranscript.length,
      toolCallCount: turnState.toolCallCount,
      audioCount: turnState.audioCount
    });

    // Clear the progress line
    process.stdout.clearLine();
    process.stdout.cursorTo(0);

    // Print final transcripts from turn state
    console.log('\n' + '='.repeat(60));
    console.log('FINAL TRANSCRIPTS:');
    console.log('='.repeat(60));

    if (turnState.inputTranscript) {
      console.log(`📝 You: ${turnState.inputTranscript}`);
    }

    if (turnState.outputTranscript) {
      if (turnState.toolCallCount > 0) {
        console.log(`🤖 Gemini (after tool): ${turnState.outputTranscript}`);
      } else {
        console.log(`🤖 Gemini: ${turnState.outputTranscript}`);
      }
    } else {
      console.log('⚠️  NO OUTPUT TRANSCRIPT CAPTURED');
    }

    console.log('='.repeat(60));

    const toolInfo = turnState.toolCallCount > 0 ? `, ${turnState.toolCallCount} tool call(s)` : '';
    const audioInfo = turnState.audioCount > 0 ? `, ${turnState.audioCount} audio chunks` : '';
    console.log(`\n✓ Done (${((Date.now() - startTime) / 1000).toFixed(1)}s${toolInfo}${audioInfo})`);

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
    console.log('🧪 PHASE 1 TEST - Tool Calling Only (No Files Written Yet)');
    console.log('─'.repeat(55));
    console.log('Test commands:');
    console.log('  1. "Write a test description" → Should call write_artifact');
    console.log('  2. "Read the description"     → Should call read_artifact');
    console.log('  3. "I like blue buttons"      → Should call route_intent');
    console.log('');
    console.log('Expected: Tool calls appear in bordered boxes');
    console.log('Note: Phase 1 only LOGS what would happen, doesn\'t write files');
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