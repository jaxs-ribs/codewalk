# Text Wrapping Implementation

## Overview
Implemented automatic text wrapping for long messages in the TUI to prevent overflow and maintain readability.

## Features

### Line Width Limit
- Maximum line width: **100 characters**
- Automatically wraps lines that exceed this limit
- Preserves readability while maximizing information density

### Smart Wrapping
- **Prefix Preservation**: Keeps prefixes like `[ASR]`, `[PLAN]`, `Claude:` on first line
- **Word Boundary Breaking**: Prefers to break at spaces and punctuation
- **Continuation Indentation**: Wrapped lines are indented with 2 spaces
- **Forced Breaking**: Handles very long words without spaces

### Wrapped Components
1. **Output Pane**: All messages in the main output area
2. **Error Dialog**: Error messages and details
3. **Future-Ready**: TextWrapper utility can be used for any text display

## Implementation Details

### TextWrapper Utility (`utils/text_wrap.rs`)
```rust
const MAX_LINE_WIDTH: usize = 100;
const CONTINUATION_INDENT: &str = "  ";
```

Key methods:
- `wrap_line()`: Wraps a single line
- `extract_prefix()`: Identifies and preserves known prefixes
- `find_break_point()`: Finds optimal break position

### Integration Points

1. **App Output** (`app.rs`):
   - Wraps lines when appending to output
   - Maintains scroll position correctly

2. **Error Dialog** (`ui/error_dialog.rs`):
   - Wraps error messages and details
   - Preserves formatting in dialog

3. **Styles** (`ui/styles.rs`):
   - Continuation lines styled in gray
   - Original prefix colors preserved

## Examples

### Before (Overflow):
```
[ASR] This is a very long transcription that goes on and on and on and definitely needs to be wrapped because it's way too long for a single line and would overflow the terminal width if not wrapped properly
```

### After (Wrapped):
```
[ASR] This is a very long transcription that goes on and on and on and definitely needs to be 
  wrapped because it's way too long for a single line and would overflow the terminal width if not 
  wrapped properly
```

## Benefits
1. **No Horizontal Scrolling**: All content visible without side-scrolling
2. **Better Readability**: Lines stay within comfortable reading width
3. **Preserved Context**: Prefixes and formatting maintained
4. **Clean Indentation**: Visual hierarchy for wrapped content

## Testing
Run the example to see wrapping in action:
```bash
cargo run --example test_wrap -p tui-app
```

This will demonstrate:
- Short lines (no wrapping)
- Long lines with natural break points
- Lines with prefixes
- Lines without break points (forced wrapping)