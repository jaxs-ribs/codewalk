# Search → Distill

A fast, interactive search and summarization tool that combines Brave Search with Groq's Kimi K2 LLM to provide concise, well-cited summaries of web content.

## Features

- 🔍 **Web Search**: Uses Brave Search API for high-quality results
- 🤖 **AI Summarization**: Groq's Kimi K2 (256k context) provides intelligent summaries
- ⚡ **Concurrent Fetching**: Fetches multiple pages in parallel for speed
- 📝 **Citation Tracking**: All summaries include numbered citations to sources
- 🔄 **Query History**: Track and repeat recent searches
- 📊 **Detailed Logging**: Optional structured logging for debugging

## Setup

1. Clone the repository:
```bash
git clone <repo>
cd search-distill
```

2. Create a `.env` file with your API keys:
```bash
cp .env.example .env
# Edit .env and add your keys:
# BRAVE_API_KEY=your_brave_api_key
# GROQ_API_KEY=your_groq_api_key
```

3. Build and run:
```bash
cargo build --release
cargo run
```

## Usage

### Interactive Shell

```bash
# Run with logging
RUST_LOG=info cargo run

# Run without logging (cleaner output)
cargo run
```

### Commands

- `<query>` - Search and summarize any topic
- `last` - Repeat the previous query
- `history` - Show recent queries
- `help` - Show available commands
- `clear` - Clear the screen
- `quit` or `q` - Exit the program

### Examples

```
> recent AI regulations 2025
> what changed in rust 1.80
> javascript framework comparison
```

## Configuration

Environment variables (in `.env`):

- `BRAVE_API_KEY` - Your Brave Search API key (required)
- `GROQ_API_KEY` - Your Groq API key (required)
- `RESULT_COUNT` - Number of search results (default: 8)
- `FETCH_TIMEOUT_MS` - Page fetch timeout in ms (default: 15000)
- `MODEL_ID` - Groq model ID (default: moonshotai/kimi-k2-instruct-0905)

## How It Works

1. **Search**: Queries Brave Search API for relevant results
2. **Fetch**: Downloads top pages concurrently (max 4 at a time)
3. **Extract**: Converts HTML to plain text using html2text
4. **Summarize**: Sends content to Kimi K2 for intelligent summarization
5. **Display**: Shows markdown-formatted summary with citations

## Error Handling

The tool gracefully handles:
- Rate limiting (with user-friendly messages)
- Network failures (continues with available data)
- Authentication errors (clear guidance on fixing)
- Failed page fetches (falls back to search snippets)

## Performance

- Typical query: 3-5 seconds total
- Concurrent fetching: Up to 4 pages simultaneously
- Smart truncation: Limits content to prevent token overflow
- Efficient caching: Avoids duplicate recent queries

## Dependencies

- `tokio` - Async runtime
- `reqwest` - HTTP client
- `serde` - JSON parsing
- `html2text` - HTML to text conversion
- `env_logger` - Structured logging
- `futures` - Concurrent operations

## License

MIT