#!/usr/bin/env node

import 'dotenv/config';
import { GoogleGenAI } from '@google/genai';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

// Modules
import { MODEL_NAME, getConfig } from './src/config.js';
import { toolDefinitions } from './src/tools.js';
import { streamAudio, recordAudio } from './src/audio.js';
import { ToolHandler } from './src/toolHandlers.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize logging
const logsDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir);
}

const sessionId = new Date().toISOString().replace(/[:.]/g, '-');
const logFile = path.join(logsDir, `session_${sessionId}.log`);

function log(message, data = null) {
  const timestamp = new Date().toISOString();
  const logEntry = { timestamp, message, data };
  // Async write - doesn't block
  fs.appendFile(logFile, JSON.stringify(logEntry) + '\n', () => {});
}

console.log('🎤 WalkCoach Speccer - Gemini Live Edition');
console.log('📝 Session log:', path.relative(process.cwd(), logFile));
console.log('');

// Check API key
const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('❌ Error: GEMINI_API_KEY not found in .env file');
  console.error('   Create a .env file with: GEMINI_API_KEY=your_key_here');
  process.exit(1);
}

// Initialize
const ai = new GoogleGenAI({ apiKey });
const artifactsDir = path.join(__dirname, 'artifacts');
const toolHandler = new ToolHandler(artifactsDir);
const conversationHistory = [];

let session = null;
let isProcessing = false;
let recordingProcess = null;
let responseQueue = [];

// Process voice input
async function processVoice() {
  if (!session || isProcessing) return;

  isProcessing = true;
  responseQueue = [];

  try {
    const audioBuffer = await recordAudio(__dirname);

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
    const turnState = {
      inputTranscript: '',
      outputTranscript: '',
      routeInfo: null,
      toolCallCount: 0,
      wroteArtifact: false
    };

    let done = false;
    const startTime = Date.now();


    // Process messages
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

          await toolHandler.handle(msg.toolCall, session, log);
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
            turnState.inputTranscript = fragment;
          } else if (turnState.inputTranscript.length === 0) {
            turnState.inputTranscript = fragment;
          } else {
            turnState.inputTranscript += fragment;
          }

          // Show the accumulated transcript
          process.stdout.clearLine();
          process.stdout.cursorTo(0);
          process.stdout.write(`📝 You're saying: "${turnState.inputTranscript}"`);
        }

        // Output transcript - simplified since we disabled transcription for speed
        if (msg.serverContent?.outputTranscription?.text != null) {
          turnState.outputTranscript = msg.serverContent.outputTranscription.text;
        }

        // Stream audio
        if (msg.data && player.stdin && !player.killed) {
          const audioChunk = Buffer.from(msg.data, 'base64');
          player.stdin.write(audioChunk);
        }

        // Turn complete
        if (msg.serverContent?.turnComplete) {
          // Process remaining messages
          while (responseQueue.length > 0) {
            const finalMsg = responseQueue.shift();
            if (finalMsg.serverContent?.outputTranscription?.text != null) {
              turnState.outputTranscript = finalMsg.serverContent.outputTranscription.text;
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

    if (!turnState.inputTranscript) {
      console.log('⚠️  WARNING: No input transcript captured');
    } else {
      console.log(`📝 You: "${turnState.inputTranscript}"`);
    }

    if (turnState.routeInfo) {
      console.log(`📍 Classified as: ${turnState.routeInfo.intent}`);
      if (turnState.routeInfo.input_type) {
        console.log(`📍 Input type: ${turnState.routeInfo.input_type}`);
      }
    }

    // Since we disabled output transcription for speed, just indicate audio was played
    console.log(`🤖 Gemini: [Audio response played]`);

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

// Main
async function main() {
  try {
    console.log('Model:', MODEL_NAME);
    console.log('Connecting...\n');

    const config = getConfig(toolDefinitions);

    session = await ai.live.connect({
      model: MODEL_NAME,
      config: config,
      callbacks: {
        onmessage: (msg) => {
          // Queue messages for processing
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
    console.log('How to use:');
    console.log('1. Press "r" and speak your project ideas');
    console.log('2. Say "write the description" to generate artifact');
    console.log('3. Say "write the phasing" for implementation plan');
    console.log('');
    console.log('Responses:');
    console.log('• Statements get "Noted"');
    console.log('• Questions get brief answers');
    console.log('• Commands trigger actions');
    console.log('─'.repeat(40));
    console.log('\nCommands:');
    console.log('  r = Record voice');
    console.log('  q = Quit\n');
    console.log('Ready (press "r" to record):');

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

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