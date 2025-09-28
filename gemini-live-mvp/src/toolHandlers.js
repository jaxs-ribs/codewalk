import { ArtifactManager } from './artifacts.js';
import path from 'path';

export class ToolHandler {
  constructor(artifactsDir) {
    this.artifactManager = new ArtifactManager(artifactsDir);
    this.ioGuard = false;
  }

  async handle(toolCall, session, log) {
    const functionResponses = [];

    for (const fc of toolCall.functionCalls) {
      console.log('\n' + '='.repeat(60));
      console.log('🔧 TOOL CALL: ' + fc.name);
      console.log('='.repeat(60));

      if (fc.name === "route_intent") {
        const response = this.handleRouteIntent(fc.args || {}, log);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response
        });
      }
      else if (fc.name === "write_artifact") {
        const response = await this.handleWriteArtifact(fc.args || {}, log);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response
        });
      }
      else if (fc.name === "read_artifact") {
        const response = this.handleReadArtifact(fc.args || {}, log);
        functionResponses.push({
          id: fc.id,
          name: fc.name,
          response
        });
      }

      console.log('='.repeat(60));
    }

    if (functionResponses.length > 0 && session) {
      await session.sendToolResponse({ functionResponses });
    }

    return functionResponses;
  }

  handleRouteIntent({ intent, action, input_type, reasoning }, log) {
    // Safeguard: If intent is not directive/conversation, it's probably misclassified
    if (intent && intent !== 'directive' && intent !== 'conversation') {
      // Move the misclassified value to input_type where it belongs
      input_type = intent;
      intent = 'conversation';
    }

    log('ROUTE_DECISION', { intent, action, input_type, reasoning });

    console.log(`\n📍 Intent: ${intent}`);
    if (action) console.log(`📍 Action: ${action}`);
    if (input_type) console.log(`📍 Input Type: ${input_type}`);
    console.log(`📍 Reasoning: ${reasoning}`);

    // Return the classification to help Gemini decide how to respond
    return {
      success: true,
      intent: intent || 'conversation',
      action: action || null,
      input_type: input_type || null,
      reasoning: reasoning || 'No reasoning provided'
    };
  }

  async handleWriteArtifact({ artifact_type, content }, log) {
    if (this.ioGuard) {
      console.log(`\n⚠️  IoGuard active - queueing write`);
      return { success: false, error: "Another operation in progress" };
    }

    this.ioGuard = true;
    console.log(`\n📝 Writing ${artifact_type}...`);

    try {
      const fileName = `${artifact_type}.md`;
      this.artifactManager.atomicWrite(fileName, content);

      log('ARTIFACT_WRITTEN', { artifact_type, length: content.length });

      // Show preview
      console.log(`\n📄 Preview of ${artifact_type}:`);
      console.log('─'.repeat(40));
      const preview = content.split('\n').slice(0, 5).join('\n');
      console.log(preview.substring(0, 300) + '...');
      console.log('─'.repeat(40));

      return {
        success: true,
        message: `Wrote ${artifact_type} (${content.length} chars)`,
        path: fileName
      };
    } catch (error) {
      console.error(`\n❌ Write failed: ${error.message}`);
      return { success: false, error: error.message };
    } finally {
      this.ioGuard = false;
    }
  }

  handleReadArtifact({ artifact_type, phase_number }, log) {
    try {
      const fileName = `${artifact_type}.md`;

      if (this.artifactManager.exists(fileName)) {
        const content = this.artifactManager.read(fileName);
        console.log(`\n📖 Read ${artifact_type} (${content.length} chars)`);

        return {
          success: true,
          content,
          artifact_type
        };
      } else {
        console.log(`\n⚠️  ${artifact_type}.md not found`);
        return {
          success: false,
          error: `${artifact_type}.md does not exist yet`
        };
      }
    } catch (error) {
      return { success: false, error: error.message };
    }
  }
}