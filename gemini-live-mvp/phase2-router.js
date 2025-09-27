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
  if (message.includes('TRANSCRIPT') || message.includes('ERROR') || message.includes('ROUTE')) {
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

console.log('🎤 WalkCoach Speccer - Phase 2: Router Implementation');
console.log('   Testing conservative intent classification\n');

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
        required: ["intent", "reasoning"]
      }
    }
  ]
}];

// PHASE 2: Conservative Router Prompt from WalkCoach
const ROUTER_PROMPT = `You are the router for WalkCoach, a voice-first project speccer.

CRITICAL ROUTING RULES:
1. DEFAULT to "conversation" unless there's an EXPLICIT command
2. Users will mostly be sharing ideas, not giving commands
3. Be VERY conservative about interpreting as directives

Only classify as "directive" for these EXPLICIT commands:
- "write the description" / "write description"
- "write the phasing" / "write phasing"
- "read the description" / "read description"
- "read the phasing" / "read phasing"
- "read phase [number]"
- "edit the description" / "edit description"
- "edit the phasing" / "edit phasing"
- "edit phase [number]"
- "copy description" / "copy phasing" / "copy both"
- Navigation: "next phase", "previous phase", "stop", "repeat"

Everything else is CONVERSATION, including:
- Project descriptions ("I want to build...")
- Feature requests ("It should have...")
- Questions ("Can it do...?")
- Clarifications ("Make sure it...")
- Vague requests ("Let's add...")

When you identify a directive, set action to one of:
- write_description
- write_phasing
- read_description
- read_phasing
- read_phase_N (where N is the phase number)
- edit_description
- edit_phasing
- edit_phase_N
- navigate_next
- navigate_previous
- stop
- repeat

ALWAYS use the route_intent tool to classify every user input.`;

// PHASE 2: Conversation prompt - respond with "Noted" to statements
const CONVERSATION_PROMPT = `You are WalkCoach, a passive note-taker for project specs.

CRITICAL BEHAVIOR:
- STATEMENTS → Respond ONLY "Noted"
- TECHNICAL QUESTIONS → 2-3 sentence answer
- YES/NO QUESTIONS → Clear yes/no + ONE sentence
- BRAINSTORMING → 2-3 concrete suggestions

You're a SINK for ideas. Default to brief acknowledgments.
When in doubt, just say "Noted".`;

const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: `${ROUTER_PROMPT}\n\n${CONVERSATION_PROMPT}`,
  temperature: 0.3, // Lower temperature for more consistent routing
  tools
};

console.log('Model:', MODEL_NAME);
console.log('Router: Conservative (defaults to conversation)');
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

// Handle tool calls - Phase 2: Focus on router behavior
async function handleToolCall(toolCall) {
  const functionResponses = [];

  for (const fc of toolCall.functionCalls) {
    console.log('\n' + '='.repeat(60));
    console.log('🔧 TOOL CALL: ' + fc.name);
    console.log('='.repeat(60));

    if (fc.name === "route_intent") {
      const { intent, action, reasoning } = fc.args || {};

      // Log routing decision
      log('ROUTE_DECISION', { intent, action, reasoning });

      console.log(`\n📍 ROUTING DECISION:`);
      console.log(`   Intent: ${intent}`);
      if (action) console.log(`   Action: ${action}`);
      console.log(`   Reasoning: ${reasoning}`);

      // Color code the output
      if (intent === 'directive') {
        console.log(`\n   ✅ DIRECTIVE DETECTED - Would execute: ${action}`);
      } else {
        console.log(`\n   💬 CONVERSATION - Will respond conversationally`);
      }

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

    else if (fc.name === "write_artifact") {
      const { artifact_type, content } = fc.args || {};
      console.log(`\n→ Would write ${artifact_type} with ${content?.length || 0} characters`);

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: {
          success: true,
          message: `Test: Would write ${artifact_type}`,
          artifact_type
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

    console.log('='.repeat(60));
  }

  // Send tool responses back
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

    // Turn state tracking
    let turnState = {
      inputTranscript: '',
      outputTranscript: '',
      toolCallCount: 0,
      audioCount: 0,
      routeIntent: null
    };

    let done = false;
    const startTime = Date.now();

    while (!done) {
      if (responseQueue.length > 0) {
        const msg = responseQueue.shift();

        // Handle tool calls
        if (msg.toolCall) {
          turnState.toolCallCount++;

          // Check if this is a route_intent call
          const routeCall = msg.toolCall.functionCalls?.find(fc => fc.name === 'route_intent');
          if (routeCall) {
            turnState.routeIntent = routeCall.args?.intent;
          }

          await handleToolCall(msg.toolCall);
          continue;
        }

        // Skip code execution attempts
        if (msg.serverContent?.modelTurn?.parts?.some(p => p.executableCode || p.codeExecutionResult)) {
          continue;
        }

        // Accumulate input transcript
        if (msg.serverContent?.inputTranscription?.text != null) {
          const text = msg.serverContent.inputTranscription.text;
          turnState.inputTranscript = text;
        }

        // Accumulate output transcript
        if (msg.serverContent?.outputTranscription?.text != null) {
          const fragment = msg.serverContent.outputTranscription.text;
          const prevTranscript = turnState.outputTranscript;

          // Better accumulation logic
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
          turnState.audioCount++;
        }

        // Turn complete
        if (msg.serverContent?.turnComplete) {
          // Process remaining messages
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
        console.log('\n⚠️  Safety timeout (90s)');
        done = true;
      }
    }

    if (player.stdin && !player.killed) {
      player.stdin.end();
    }

    // Print final results
    console.log('\n' + '='.repeat(60));
    console.log('TURN SUMMARY:');
    console.log('='.repeat(60));

    if (turnState.inputTranscript) {
      console.log(`📝 You said: "${turnState.inputTranscript}"`);
    }

    if (turnState.routeIntent) {
      console.log(`📍 Classified as: ${turnState.routeIntent.toUpperCase()}`);
    }

    if (turnState.outputTranscript) {
      console.log(`🤖 Gemini responded: "${turnState.outputTranscript}"`);
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
    console.log('🧪 PHASE 2 TEST - Conservative Router');
    console.log('─'.repeat(55));
    console.log('Test these inputs to verify routing:');
    console.log('');
    console.log('SHOULD BE CONVERSATION (respond with "Noted"):');
    console.log('  • "I want to build a snake game"');
    console.log('  • "It should have blue buttons"');
    console.log('  • "Make sure it works on mobile"');
    console.log('');
    console.log('SHOULD BE DIRECTIVE (execute action):');
    console.log('  • "Write the description"');
    console.log('  • "Read the phasing"');
    console.log('  • "Edit phase 2"');
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