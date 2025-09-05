use crate::constants::prefixes;

const MAX_LINE_WIDTH: usize = 100;
const CONTINUATION_INDENT: &str = "  ";

pub struct TextWrapper;

impl TextWrapper {
    /// Wrap a single line of text to fit within MAX_LINE_WIDTH
    pub fn wrap_line(line: &str) -> Vec<String> {
        if line.chars().count() <= MAX_LINE_WIDTH {
            return vec![line.to_string()];
        }
        
        // Check if line has a prefix we should preserve
        let (prefix, content) = Self::extract_prefix(line);
        let prefix_len_chars = prefix.chars().count();
        
        let mut wrapped = Vec::new();
        let mut remaining = content;
        let mut is_first = true;
        
        // Calculate available width for content
        let first_line_width = MAX_LINE_WIDTH.saturating_sub(prefix_len_chars);
        let continuation_width = MAX_LINE_WIDTH.saturating_sub(CONTINUATION_INDENT.chars().count());
        
        while !remaining.is_empty() {
            let available_width = if is_first { first_line_width } else { continuation_width };
            
            // Find a good break point
            let break_point = Self::find_break_point(remaining, available_width);
            
            if is_first {
                let mut first_line = String::from(prefix);
                first_line.push_str(&remaining[..break_point]);
                wrapped.push(first_line);
                is_first = false;
            } else {
                wrapped.push(format!("{}{}", CONTINUATION_INDENT, &remaining[..break_point]));
            }
            
            remaining = remaining[break_point..].trim_start();
        }
        
        if wrapped.is_empty() {
            vec![line.to_string()]
        } else {
            wrapped
        }
    }
    
    /// Extract known prefixes from the line
    fn extract_prefix(line: &str) -> (&str, &str) {
        for prefix in &[
            prefixes::CLAUDE,
            prefixes::USER,
            prefixes::SYSTEM,
            prefixes::ERROR,
            "Claude:",
            "System:",
        ] {
            if line.starts_with(prefix) {
                // Include the space after the prefix if present
                let prefix_with_space = if line.len() > prefix.len() && 
                                           line.chars().nth(prefix.len()) == Some(' ') {
                    &line[..prefix.len() + 1]
                } else {
                    prefix
                };
                return (prefix_with_space, &line[prefix_with_space.len()..]);
            }
        }
        
        // No known prefix
        ("", line)
    }
    
    /// Find a good break point in the text (prefer breaking at spaces)
    fn find_break_point(text: &str, max_width: usize) -> usize {
        let mut char_count = 0usize;
        let mut fallback_end = 0usize;
        let mut last_space_byte: Option<usize> = None;
        let mut last_space_chars: usize = 0;

        for (byte_idx, ch) in text.char_indices() {
            let ch_len = ch.len_utf8();
            char_count += 1;
            let end_byte = byte_idx + ch_len;
            if char_count <= max_width { 
                fallback_end = end_byte; 
            }
            if ch == ' ' {
                last_space_byte = Some(byte_idx);
                last_space_chars = char_count;
            }
            if char_count >= max_width {
                break;
            }
        }

        // If the whole text fits within max_width chars
        if text.chars().count() <= max_width {
            return text.len();
        }

        let half = max_width / 2;
        if let Some(b) = last_space_byte {
            if last_space_chars > half {
                return b + 1;
            }
        }
        
        // Fallback: break at boundary after max_width-th char
        fallback_end
    }
}