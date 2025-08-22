use crate::constants::prefixes;

const MAX_LINE_WIDTH: usize = 100;
const CONTINUATION_INDENT: &str = "  ";

pub struct TextWrapper;

impl TextWrapper {
    /// Wrap a single line of text to fit within MAX_LINE_WIDTH
    pub fn wrap_line(line: &str) -> Vec<String> {
        if line.len() <= MAX_LINE_WIDTH {
            return vec![line.to_string()];
        }
        
        // Check if line has a prefix we should preserve
        let (prefix, content) = Self::extract_prefix(line);
        let prefix_len = prefix.len();
        
        let mut wrapped = Vec::new();
        let mut remaining = content;
        let mut is_first = true;
        
        // Calculate available width for content
        let first_line_width = MAX_LINE_WIDTH.saturating_sub(prefix_len);
        let continuation_width = MAX_LINE_WIDTH.saturating_sub(CONTINUATION_INDENT.len());
        
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
            prefixes::ASR,
            prefixes::PLAN,
            prefixes::EXEC,
            prefixes::WARN,
            prefixes::UTTERANCE,
            "Claude:",
            "Devin:",
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
        if text.len() <= max_width {
            return text.len();
        }
        
        // Try to break at a space
        if let Some(last_space) = text[..max_width].rfind(' ') {
            // Don't break too early (at least 50% of available width)
            if last_space > max_width / 2 {
                return last_space + 1; // Include the space in the current line
            }
        }
        
        // Try to break at other punctuation
        for delim in &[',', '.', ';', ':', '!', '?', '-', '/', '\\'] {
            if let Some(pos) = text[..max_width].rfind(*delim) {
                if pos > max_width / 2 {
                    return pos + 1;
                }
            }
        }
        
        // Last resort: break at max_width
        max_width
    }
    
    /// Wrap multiple lines
    pub fn wrap_lines(lines: &[String]) -> Vec<String> {
        lines.iter()
            .flat_map(|line| Self::wrap_line(line))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_short_line() {
        let line = "This is a short line";
        let wrapped = TextWrapper::wrap_line(line);
        assert_eq!(wrapped, vec!["This is a short line"]);
    }
    
    #[test]
    fn test_long_line() {
        let line = "This is a very long line that definitely exceeds our maximum width limit and needs to be wrapped into multiple lines for proper display";
        let wrapped = TextWrapper::wrap_line(&line);
        assert!(wrapped.len() > 1);
        assert!(wrapped.iter().all(|l| l.len() <= MAX_LINE_WIDTH));
    }
    
    #[test]
    fn test_prefix_preservation() {
        let line = "[ASR] This is a very long transcription that goes on and on and on and definitely needs to be wrapped because it's way too long for a single line";
        let wrapped = TextWrapper::wrap_line(&line);
        assert!(wrapped[0].starts_with("[ASR]"));
        assert!(wrapped[1].starts_with(CONTINUATION_INDENT));
    }
}