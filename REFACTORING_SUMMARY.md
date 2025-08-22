# Crate Refactoring and Memory Implementation

## Crate Renaming
Successfully renamed all crates to be more descriptive of their functionality:

### Old → New Names
- `tui-app` → `orchestrator` - Central coordinator for the entire system
- `llm-interface` → `router` - Routes commands to appropriate executors  
- `llm-client` → `llm` - Universal LLM client library
- `audio-transcribe` → `stt` - Speech-to-text functionality

### Rationale
- **orchestrator**: Better describes its role as the central coordinator
- **router**: Clearer that it routes commands, not just an LLM interface
- **llm**: Simpler, more direct name for the LLM client
- **stt**: Industry-standard abbreviation for speech-to-text

## Conversation Memory Implementation

Added conversation memory to the router to maintain context across interactions:

### Features
- **Rolling History**: Maintains last 10 messages (configurable)
- **Context Aware**: Router now understands conversation flow
- **Automatic Management**: Old messages auto-removed when limit reached
- **Timestamped**: Each message includes timestamp for tracking

### Memory Structure
```rust
pub struct ConversationMemory {
    messages: VecDeque<Message>,
    max_size: usize,
}

pub struct Message {
    pub role: MessageRole,
    pub content: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}
```

### Integration Points
1. **GroqProvider**: Automatically tracks all interactions
2. **System Prompt**: Includes conversation history for context
3. **Decision Making**: Router can now make context-aware decisions

## Benefits

### Better Context Understanding
- Router knows what was discussed in previous messages
- Can handle follow-up questions and references
- Understands ongoing tasks and context

### Prompt Caching Optimization
- With Kimi K2: Stable system prompt enables caching
- History appended after cached portion
- Reduces token costs while maintaining context

### Future Extensibility
- Easy to add persistence (save/load conversations)
- Can expand to include executor outputs
- Ready for multi-turn conversations

## Usage Example

When user says:
1. "Help me fix the bug in authentication"
2. "Actually, let's focus on the login part first"
3. "Can you add logging to debug it?"

The router now understands:
- Message 2 refers to the authentication bug from message 1
- Message 3 refers to the login part from message 2
- All three are part of the same debugging task

## Migration Notes

### For Existing Code
Update imports:
```rust
// Old
use audio_transcribe::...;
use llm_interface::...;
use llm_client::...;
use tui_app::...;

// New
use stt::...;
use router::...;
use llm::...;
use orchestrator::...;
```

### For New Features
The memory is automatic - no code changes needed unless you want to:
- Adjust history size
- Add persistence
- Access conversation history directly

## Testing
```bash
# Build all renamed crates
cargo build

# Run the orchestrator
cargo run --bin codewalk

# Test router with memory
cargo run --example test_router -p router
```

The system now has:
1. ✅ Clearer, more descriptive crate names
2. ✅ Conversation memory for context awareness
3. ✅ Optimized for prompt caching with Kimi K2
4. ✅ Ready for multi-turn conversations