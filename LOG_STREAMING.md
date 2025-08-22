# Live Log Streaming Implementation

## Overview
Implemented a comprehensive log monitoring and streaming system for Claude Code sessions, displaying real-time logs in a dedicated pane on the right side of the TUI.

## Architecture

### Log Monitoring System
1. **Log Monitor Module** (`log_monitor.rs`)
   - Watches for JSONL files in `~/.claude/projects/` or session-specific directories
   - Uses file system notifications for real-time updates
   - Parses JSONL entries into structured log data
   - Supports both polling and file watching for maximum reliability

2. **Log Types**
   - UserMessage: User inputs to Claude
   - AssistantMessage: Claude's responses
   - ToolCall: When Claude invokes tools
   - ToolResult: Results from tool executions
   - Status: Status updates
   - Error: Error messages

3. **Live Streaming**
   - Uses async channels (mpsc) for communication
   - Non-blocking log reception in main loop
   - Automatic scrolling with manual override
   - Memory management (max 1000 log entries)

## UI Components

### Layout Changes
- Split main content area 60/40 (output/logs)
- Left pane: Output messages (60%)
- Right pane: Session logs (40%)
- Bottom: Help and input remain unchanged

### Log Pane Features
- **Auto-scroll**: Follows latest logs by default
- **Manual scroll**: Same controls as output pane
- **Visual indicators**: Different colors for log types
- **Truncation**: Long messages truncated to fit
- **Scroll position**: Shows position when manually scrolling

## Log Entry Format

### JSONL Structure
```json
{
  "type": "user_message|assistant_message|tool_call|etc",
  "timestamp": "2024-01-20T10:30:00Z",
  "content": {...},
  "tool": "tool_name",
  "message": "human readable message"
}
```

### Display Format
```
[USER] User's command to Claude
[ASST] Claude's response
[TOOL] Tool invocation
[RSLT] Tool result
[STAT] Status update
[ERR!] Error message
```

## Integration Points

### Session Start
When launching Claude executor:
1. Creates logs directory in working directory (if possible)
2. Starts log monitor for that directory
3. Falls back to `~/.claude/projects/` monitoring

### Real-time Updates
1. File watcher detects new/modified JSONL files
2. Parser extracts structured data
3. Channel sends parsed logs to UI
4. UI updates log pane with new entries

## Color Coding
- **Blue**: User messages
- **Green**: Assistant messages
- **Yellow**: Tool calls
- **Cyan**: Tool results
- **Gray**: Status updates
- **Red**: Errors

## Performance Optimizations

### Memory Management
- Maximum 1000 log entries retained
- Older entries automatically removed
- Scroll position adjusted when trimming

### Non-blocking Operations
- Async file reading
- Try-receive for log polling
- Batch processing (up to 10 logs per tick)

## Usage

### Viewing Logs
- Logs appear automatically when Claude session starts
- Right pane shows real-time session activity
- Use arrow keys to scroll through history

### Scroll Controls
- **↑/↓**: Scroll one line
- **PgUp/PgDn**: Page scroll
- **Home**: Jump to first log
- **End**: Jump to latest (re-enables auto-scroll)

## Benefits

1. **Real-time Visibility**: See exactly what Claude is doing
2. **Debug Capability**: Understand tool calls and responses
3. **Session History**: Review past actions in session
4. **Non-intrusive**: Separate pane doesn't interfere with main output
5. **Performance**: Efficient streaming without blocking UI

## Future Enhancements

Potential improvements:
- Filter logs by type
- Search within logs
- Export session logs
- Persist logs between sessions
- Configure log directory via settings
- Support for different log formats

## Technical Notes

### File Watching
Uses `notify` crate for cross-platform file system events:
- Linux: inotify
- macOS: FSEvents
- Windows: ReadDirectoryChangesW

### Log Discovery
Priority order:
1. Session-specific `logs/` directory in working directory
2. Claude's default `~/.claude/projects/` directory
3. Finds latest JSONL file by modification time

### Error Handling
- Graceful fallback if log files not found
- Continues operation if log monitoring fails
- Channel disconnection handled cleanly