# Error Handling and Scrolling Features

## New Features Added

### 1. Error Dialog Display
- Shows detailed error information when pipeline failures occur
- Covers ASR failures, LLM routing failures, and executor launch failures
- Dismissible with Enter or Escape keys
- Red border with clear error title and details

### 2. Message Scrolling
- **Auto-scroll**: Automatically shows latest messages (default)
- **Manual scroll**: Use arrow keys to browse message history
- **Scroll indicator**: Shows position when manually scrolling

## Keyboard Controls

### Scrolling Controls
- **↑/↓**: Scroll up/down one line
- **PgUp/PgDn**: Page up/down (10 lines)
- **Home**: Jump to first message
- **End**: Jump to latest message (re-enables auto-scroll)

### Error Dialog
- **Enter/Escape**: Dismiss error dialog

## Implementation Details

### Error Handling Points
1. **Recording Start/Stop**: Shows error if audio backend fails
2. **Audio Processing**: Shows error if transcription fails
3. **LLM Routing**: Shows error if LLM call fails or response parsing fails
4. **Executor Launch**: Shows error if executor binary not found or launch fails

### Scroll State Management
- Auto-scroll enabled by default
- Disabled when user manually scrolls up
- Re-enabled when scrolling to bottom (End key or scrolling down to end)
- Scroll position indicator appears when not auto-scrolling

## Testing Scenarios

### Test Error Dialog
1. Temporarily break GROQ_API_KEY to trigger LLM error
2. Try launching non-existent executor
3. Verify error dialog appears with details
4. Press Enter/Escape to dismiss

### Test Scrolling
1. Generate many messages (record multiple times)
2. Use arrow keys to scroll up through history
3. Notice scroll indicator appears
4. Press End to jump back to latest
5. Verify auto-scroll resumes

## Code Structure

### New Types
- `ErrorInfo`: Stores error title, message, and optional details
- `ScrollState`: Manages scroll position and auto-scroll flag
- `ScrollDirection`: Enum for scroll operations

### New UI Components
- `error_dialog.rs`: Renders error dialog overlay
- Updated `OutputPane`: Implements scrollable message view

### Modified App State
- Added `error_info: Option<ErrorInfo>` for current error
- Added `scroll: ScrollState` for scroll management
- Added `Mode::ShowingError` for error dialog state

## Benefits
1. **Better User Feedback**: Clear error messages instead of silent failures
2. **Message History**: Can review older messages even after they scroll off
3. **Improved UX**: Natural scrolling controls familiar to terminal users
4. **Debug Capability**: Can see full error details for troubleshooting