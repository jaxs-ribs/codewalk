use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use chrono::Local;
use std::sync::Mutex;
use lazy_static::lazy_static;

lazy_static! {
    static ref LOG_FILE: Mutex<Option<PathBuf>> = Mutex::new(None);
}

/// Initialize logging to a file in the logs directory
pub fn init_logging() -> anyhow::Result<()> {
    eprintln!("DEBUG: Starting logger init");
    
    // Create logs directory if it doesn't exist
    let logs_dir = PathBuf::from("logs");
    if !logs_dir.exists() {
        eprintln!("DEBUG: Creating logs directory");
        fs::create_dir_all(&logs_dir)?;
    }
    
    // Generate log file name with timestamp
    let timestamp = Local::now().format("%Y%m%d_%H%M%S");
    let log_file = logs_dir.join(format!("orchestrator_{}.log", timestamp));
    
    eprintln!("DEBUG: Log file will be: {}", log_file.display());
    
    // Store the log file path
    let mut log_path = LOG_FILE.lock().unwrap();
    *log_path = Some(log_file.clone());
    drop(log_path); // Release the lock before calling log_line
    
    // Write initial header
    log_line(&format!("=== Orchestrator Log Started at {} ===", Local::now()));
    log_line(&format!("Log file: {}", log_file.display()));
    
    // Use eprintln to ensure it shows even if TUI starts
    eprintln!("Logging to: {}", log_file.display());
    
    Ok(())
}

/// Write a line to the log file
pub fn log_line(message: &str) {
    if let Ok(log_path) = LOG_FILE.lock() {
        if let Some(ref path) = *log_path {
            if let Ok(mut file) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
            {
                let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
                let _ = writeln!(file, "[{}] {}", timestamp, message);
            }
        }
    }
}

/// Log an event with a category
pub fn log_event(category: &str, message: &str) {
    log_line(&format!("[{}] {}", category, message));
    // Don't print to console when TUI is active - it interferes
    // eprintln!("[{}] {}", category, message);
}

/// Log an error
pub fn log_error(context: &str, error: &str) {
    log_line(&format!("[ERROR] {}: {}", context, error));
    // Don't print to console when TUI is active
    // eprintln!("[ERROR] {}: {}", context, error);
}

/// Log debug info (only to file, not console)
pub fn log_debug(message: &str) {
    log_line(&format!("[DEBUG] {}", message));
}