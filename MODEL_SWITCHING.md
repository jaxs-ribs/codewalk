# Model Switching Guide

## Available Models

The LLM interface now supports switching between two Groq models:

1. **Llama 3.1 8B Instant** (default)
   - Fast, reliable, no prompt caching
   - Use when Kimi K2 is over capacity
   - Shorter system prompts for efficiency

2. **Kimi K2 Instruct** 
   - Advanced model with prompt caching
   - 10-20x faster after first request (caching)
   - 50% token cost savings with caching
   - May have capacity limits

## How to Switch Models

### Method 1: Environment Variable
Set `GROQ_MODEL` in your `.env` file:

```bash
# For Llama 3.1 8B (default)
GROQ_MODEL=llama-3.1-8b-instant

# For Kimi K2 (when available)
GROQ_MODEL=moonshotai/kimi-k2-instruct
```

### Method 2: Runtime Switch
Export before running:

```bash
# Use Llama
export GROQ_MODEL=llama-3.1-8b-instant
cargo run -p tui-app

# Use Kimi K2
export GROQ_MODEL=moonshotai/kimi-k2-instruct
cargo run -p tui-app
```

## Performance Comparison

### Kimi K2 (with caching)
- First request: ~1800ms
- Subsequent: ~400-600ms (cached)
- Best for repeated use

### Llama 3.1 8B
- Consistent: ~1000-2000ms
- No caching overhead
- More reliable availability

## When to Use Which

**Use Kimi K2 when:**
- You need fastest response times
- Making many similar requests
- Model is available (not over capacity)

**Use Llama 3.1 8B when:**
- Kimi K2 is over capacity
- You need reliable availability
- Making one-off requests

## Testing

Run the test example to verify model switching:

```bash
# Test with default (Llama)
cargo run --example test_model -p llm-interface

# Test with Kimi K2
GROQ_MODEL=moonshotai/kimi-k2-instruct cargo run --example test_model -p llm-interface
```

The active model will be logged on startup:
```
GroqProvider initialized with model: llama-3.1-8b-instant
```