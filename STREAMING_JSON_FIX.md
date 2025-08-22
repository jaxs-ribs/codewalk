# Claude Streaming JSON Integration

## Problem
The session logs pane was empty because Claude wasn't outputting structured logs when launched in headless mode with just the `-p` flag.

## Solution
Updated Claude executor to use streaming JSON output format and parse the JSON directly from stdout.

### Changes Made

1. **Added Claude CLI Flags** (`executor/claude.rs`):
   ```rust
   // Add streaming JSON output for better logging
   cmd.arg("--output-format")
      .arg("stream-json");
   
   // Add verbose mode for detailed logging
   cmd.arg("--verbose");
   ```

2. **JSON Parsing in App** (`app.rs`):
   - Added `parse_claude_json()` to parse streaming JSON lines
   - Added `extract_json_content()` to extract human-readable content
   - Modified `poll_executor_output()` to parse JSON and populate session logs

3. **Log Entry Processing**:
   - Parses each JSON line from Claude's stdout
   - Determines log type (user, assistant, tool, error, etc.)
   - Extracts content from various JSON structures
   - Adds to session_logs for display in right pane

## Streaming JSON Format

Claude outputs JSON lines like:
```json
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Your prompt"}]}}
{"type":"tool_use","name":"Edit","input":{...}}
{"type":"tool_result","output":"Success"}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Response"}]}}
```

## Display in UI

The logs now appear in the right pane with color coding:
- [USER] - Blue - User messages
- [ASST] - Green - Assistant responses  
- [TOOL] - Yellow - Tool invocations
- [RSLT] - Cyan - Tool results
- [STAT] - Gray - Status updates
- [ERR!] - Red - Errors

## Benefits

1. **Real-time Visibility**: See Claude's actions as they happen
2. **Structured Data**: JSON format provides rich metadata
3. **Tool Tracking**: Clear visibility of which tools Claude uses
4. **Error Detection**: Immediate error visibility
5. **Verbose Mode**: Detailed logging for debugging

## Usage

When you launch a Claude session now:
1. Claude runs with `--output-format stream-json --verbose`
2. Each JSON line is parsed in real-time
3. Logs appear immediately in the right pane
4. Scroll through logs with arrow keys

The logs are now populated directly from Claude's streaming output rather than trying to find log files on disk.