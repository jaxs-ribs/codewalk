use anyhow::{Result, anyhow};

pub fn load_api_key() -> Result<String> {
    // Try environment variable first
    if let Ok(key) = std::env::var("GROQ_API_KEY") {
        return Ok(key);
    }
    
    // Fall back to .env file if it exists
    load_env_file_if_present(".env");
    get_groq_api_key()
}

/// Load environment variables from .env at repo root (best-effort).
/// This is used to populate RELAY_* and optional keys without requiring shell exports.
pub fn load_dotenv() {
    // Try common locations relative to current working directory
    // 1) current dir, 2) parent, 3) grandparent
    load_env_file_if_present(".env");
    load_env_file_if_present("../.env");
    load_env_file_if_present("../../.env");
}

fn load_env_file_if_present(path: &str) {
    if let Ok(content) = std::fs::read_to_string(path) {
        parse_env_file(&content);
    }
}

fn parse_env_file(content: &str) {
    for line in content.lines() {
        if is_valid_env_line(line) {
            apply_env_variable(line);
        }
    }
}

fn is_valid_env_line(line: &str) -> bool {
    let trimmed = line.trim();
    !trimmed.is_empty() && !trimmed.starts_with('#')
}

fn apply_env_variable(line: &str) {
    if let Some((key, value)) = parse_key_value(line.trim()) {
        set_env_if_unset(key, value);
    }
}

fn parse_key_value(line: &str) -> Option<(String, String)> {
    let mut parts = line.splitn(2, '=');
    let key = parts.next()?.trim();
    let value = extract_value(parts.next()?.trim());
    
    if key.is_empty() {
        return None;
    }
    
    Some((key.to_string(), value))
}

fn extract_value(raw_value: &str) -> String {
    raw_value
        .trim_matches('"')
        .trim_matches('\'')
        .to_string()
}

fn set_env_if_unset(key: String, value: String) {
    if std::env::var(&key).is_err() {
        unsafe {
            std::env::set_var(key, value);
        }
    }
}

fn get_groq_api_key() -> Result<String> {
    std::env::var("GROQ_API_KEY")
        .map_err(|_| anyhow!("GROQ_API_KEY not found. Please set it as an environment variable"))
}
