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

// Session logging
const sessionId = new Date().toISOString().replace(/[:.]/g, '-');
const logFile = path.join(logsDir, `session_${sessionId}.log`);

function log(message, data = null) {
  const timestamp = new Date().toISOString();
  const logEntry = { timestamp, message, data };
  fs.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');
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

console.log('🎤 WalkCoach Speccer - Phase 4-5: Passive Conversation + Enhanced Phasing');
console.log(`📝 Session log: ${logFile}\n`);

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
          input_type: {
            type: "STRING",
            enum: ["statement", "yes_no_question", "technical_question", "brainstorming", "unclear"],
            description: "Type of conversational input"
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

// PHASE 4 & 5: Enhanced system prompt with refined conversation and phasing rules
const SYSTEM_PROMPT = `You are WalkCoach, a voice-first project speccer that acts as a passive note-taker.

ROUTING RULES:
- DEFAULT to "conversation" unless there's an EXPLICIT command
- Only classify as "directive" for: "write the description", "write the phasing", "read the description", etc.
- Everything else is CONVERSATION
- Also classify the input_type for conversation: statement, yes_no_question, technical_question, brainstorming

PHASE 4 - PASSIVE CONVERSATION BEHAVIOR:
When intent is "conversation", ALWAYS respond based on input_type:
- statement → Respond EXACTLY "Noted" (nothing more, nothing less)
- yes_no_question → Start with "Yes" or "No", then add ONE clarifying sentence
- technical_question → Give a 2-3 sentence technical answer
- brainstorming → Offer 2-3 concrete suggestions
- unclear → Default to "Noted"

CRITICAL: Never leave a response empty. Always provide appropriate feedback.

Examples:
- "The app needs dark mode" → "Noted"
- "Should I use React Native?" → "Yes, React Native would work well for cross-platform development."
- "How does OAuth work?" → "OAuth lets users authorize your app without sharing passwords. The user logs in with their provider, and you receive a token to access their data."
- "What features could help with onboarding?" → "You could add a guided tour, progressive disclosure of features, and preset templates to get users started quickly."

DESCRIPTION GENERATION:
Generate 1500-2500 CHARACTER markdown that:
- Uses flowing prose perfect for text-to-speech
- NO bullet points, NO lists
- Uses contractions (it's, you'll, we're)
- Writes like explaining to a friend on a walk
- Reviews ENTIRE conversation history
- Format: # Project Description\\n\\n[Natural flowing paragraphs]

PHASE 5 - ENHANCED PHASING GENERATION:
Generate EXACTLY 3-5 phases where EACH phase:
- Has a clear, specific title
- Is ONE flowing paragraph (200-400 chars)
- Describes concrete implementation steps
- MUST end with EXACTLY: "When this phase is done, you'll be able to [specific testable outcome]."
- Covers ALL features mentioned in conversation
- NO bullets, NO numbered lists

Example phase:
"## Phase 1: User Authentication System
We'll start by implementing the core authentication flow using OAuth 2.0. This involves setting up the provider connections, creating the login UI, and establishing secure session management. We'll ensure users can sign up, log in, and maintain their sessions across app restarts. When this phase is done, you'll be able to create an account and securely log into the application."

IMPORTANT:
- Always use route_intent first
- Track conversation to synthesize complete artifacts
- Be a passive listener, not an eager assistant`;

const config = {
  responseModalities: [Modality.AUDIO],
  inputAudioTranscription: {},
  outputAudioTranscription: {},
  systemInstruction: SYSTEM_PROMPT,
  temperature: 0.7,
  tools
};

console.log('Model:', MODEL_NAME);
console.log('Mode: Passive conversation + Enhanced phasing');
console.log('Connecting...\n');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

let session = null;
let recordingProcess = null;
let isProcessing = false;
let responseQueue = [];
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

// Handle tool calls
async function handleToolCall(toolCall) {
  const functionResponses = [];

  for (const fc of toolCall.functionCalls) {
    console.log('\n' + '='.repeat(60));
    console.log('🔧 TOOL CALL: ' + fc.name);
    console.log('='.repeat(60));

    if (fc.name === "route_intent") {
      const { intent, action, input_type, reasoning } = fc.args || {};

      log('ROUTE_DECISION', { intent, action, input_type, reasoning });

      console.log(`\n📍 Intent: ${intent}`);
      if (action) console.log(`📍 Action: ${action}`);
      if (input_type) console.log(`📍 Input Type: ${input_type}`);
      console.log(`📍 Reasoning: ${reasoning}`);

      functionResponses.push({
        id: fc.id,
        name: fc.name,
        response: { success: true, intent, action, input_type, reasoning }
      });
    }

    else if (fc.name === "write_artifact") {
      const { artifact_type, content } = fc.args || {};

      if (ioGuard) {
        console.log(`\n⚠️  IoGuard active - queueing write`);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response: { success: false, error: "Another operation in progress" }
        });
        continue;
      }

      ioGuard = true;
      console.log(`\n📝 Writing ${artifact_type}...`);

      try {
        const filePath = path.join(artifactsDir, `${artifact_type}.md`);
        atomicWrite(filePath, content);

        // Log the write
        log('ARTIFACT_WRITTEN', { artifact_type, length: content.length });

        // Show preview
        console.log(`\n📄 Preview of ${artifact_type}:`);
        console.log('─'.repeat(40));
        const preview = content.split('\n').slice(0, 5).join('\n');
        console.log(preview.substring(0, 300) + '...');
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

    // Check session health
    if (!session) {
      console.error('❌ Session lost - reconnecting needed');
      isProcessing = false;
      return;
    }

    try {
      await session.sendRealtimeInput({
        audio: {
          data: audioBase64,
          mimeType: 'audio/pcm;rate=16000'
        }
      });
      await session.sendRealtimeInput({ audioStreamEnd: true });
    } catch (error) {
      console.error('❌ Failed to send audio:', error.message);
      isProcessing = false;
      return;
    }

    const player = streamAudio();

    // Turn state
    let turnState = {
      inputTranscript: '',
      outputTranscript: '',
      routeInfo: null,
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

          // Clear the input transcript line when moving to tool calls
          if (turnState.inputTranscript) {
            console.log(''); // New line after input
          }

          // Capture routing info
          const routeCall = msg.toolCall.functionCalls?.find(fc => fc.name === 'route_intent');
          if (routeCall) {
            turnState.routeInfo = routeCall.args;
          }

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

        // Input transcript - accumulate properly
        if (msg.serverContent?.inputTranscription?.text != null) {
          const fragment = msg.serverContent.inputTranscription.text;

          // Check if this is a cumulative update or a fragment
          if (fragment.startsWith(turnState.inputTranscript)) {
            // This is a cumulative update that includes everything
            turnState.inputTranscript = fragment;
          } else if (turnState.inputTranscript.length === 0) {
            // First fragment
            turnState.inputTranscript = fragment;
          } else {
            // This is a continuation fragment, append it
            turnState.inputTranscript += fragment;
          }

          // Show the accumulated transcript
          process.stdout.clearLine();
          process.stdout.cursorTo(0);
          process.stdout.write(`📝 You're saying: "${turnState.inputTranscript}"`);
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

    // Log the turn
    log('TURN_COMPLETE', {
      input: turnState.inputTranscript,
      output: turnState.outputTranscript,
      routeInfo: turnState.routeInfo,
      wroteArtifact: turnState.wroteArtifact
    });

    // Print summary
    console.log('\n' + '='.repeat(60));
    console.log('TURN COMPLETE:');

    // Check for empty transcripts (indicates connection issue)
    if (!turnState.inputTranscript) {
      console.log('⚠️  WARNING: No input transcript captured');
      console.log('   Possible causes:');
      console.log('   - Audio recording issue');
      console.log('   - Connection problem');
      console.log('   - STT failure');
    } else {
      console.log(`📝 You: "${turnState.inputTranscript}"`);
    }

    if (turnState.routeInfo) {
      console.log(`📍 Classified as: ${turnState.routeInfo.intent}`);
      if (turnState.routeInfo.input_type) {
        console.log(`📍 Input type: ${turnState.routeInfo.input_type}`);
      }
    }

    if (!turnState.outputTranscript) {
      console.log('⚠️  WARNING: No response generated');
      if (turnState.routeInfo?.input_type === 'statement') {
        console.log('   Expected: "Noted"');
      }
    } else {
      console.log(`🤖 Gemini: "${turnState.outputTranscript}"`);
    }

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
    console.log('🧪 PHASE 4-5 TEST: Passive Conversation + Enhanced Phasing');
    console.log('─'.repeat(60));
    console.log('TEST PHASE 4 - Different response types:');
    console.log('  Statement: "The app needs dark mode" → "Noted"');
    console.log('  Yes/No: "Should I use React?" → "Yes..." + 1 sentence');
    console.log('  Technical: "How does OAuth work?" → 2-3 sentences');
    console.log('  Brainstorm: "What features for onboarding?" → 2-3 ideas');
    console.log('');
    console.log('TEST PHASE 5 - Enhanced phasing:');
    console.log('  1. Share multiple features/requirements');
    console.log('  2. Say "Write the phasing"');
    console.log('  3. Check that EACH phase ends with:');
    console.log('     "When this phase is done, you\'ll be able to..."');
    console.log('─'.repeat(60));
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