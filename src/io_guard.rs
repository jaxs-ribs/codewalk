use std::sync::atomic::{AtomicBool, Ordering};
use std::path::Path;

/// Global flag to track if file I/O is allowed.
/// Only the orchestrator should set this to true during action execution.
static IO_ALLOWED: AtomicBool = AtomicBool::new(false);

/// Guard that temporarily allows I/O operations.
/// When dropped, automatically disables I/O again.
pub struct IoGuard;

impl IoGuard {
    /// Create a new I/O guard, enabling file operations.
    pub fn new() -> Self {
        IO_ALLOWED.store(true, Ordering::SeqCst);
        IoGuard
    }
}

impl Drop for IoGuard {
    fn drop(&mut self) {
        IO_ALLOWED.store(false, Ordering::SeqCst);
    }
}

/// Check if I/O is currently allowed.
/// Panics if not allowed and path is in artifacts directory.
pub fn check_io_allowed(path: &Path, operation: &str) {
    // Only enforce for artifacts directory
    if !path.starts_with("artifacts/") && !path.starts_with("./artifacts/") {
        return;
    }
    
    if !IO_ALLOWED.load(Ordering::SeqCst) {
        panic!(
            "Unauthorized {} operation on {:?}. All artifact I/O must go through the orchestrator!",
            operation,
            path
        );
    }
}

/// Safe read operation that checks permissions.
pub fn safe_read(path: &Path) -> std::io::Result<String> {
    check_io_allowed(path, "read");
    std::fs::read_to_string(path)
}

/// Safe write operation that checks permissions.
pub fn safe_write(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    check_io_allowed(path, "write");
    std::fs::write(path, contents)
}

/// Safe atomic write operation.
pub fn safe_write_atomic(path: &Path, contents: &[u8]) -> anyhow::Result<()> {
    check_io_allowed(path, "write");
    
    use std::fs;
    use std::io::Write;
    use tempfile::NamedTempFile;
    
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    
    let mut temp = NamedTempFile::new_in(parent)?;
    temp.write_all(contents)?;
    temp.flush()?;
    temp.persist(path)?;
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    
    #[test]
    fn test_io_guard_allows_operations() {
        let path = PathBuf::from("artifacts/test.md");
        
        // Should panic without guard
        let result = std::panic::catch_unwind(|| {
            check_io_allowed(&path, "write");
        });
        assert!(result.is_err(), "Should panic without IoGuard");
        
        // Should succeed with guard
        {
            let _guard = IoGuard::new();
            let result = std::panic::catch_unwind(|| {
                check_io_allowed(&path, "write");
            });
            assert!(result.is_ok(), "Should succeed with IoGuard");
        }
        
        // Should panic again after guard is dropped
        let result = std::panic::catch_unwind(|| {
            check_io_allowed(&path, "write");
        });
        assert!(result.is_err(), "Should panic after IoGuard dropped");
    }
    
    #[test]
    fn test_non_artifact_paths_always_allowed() {
        let path = PathBuf::from("logs/test.log");
        
        // Should always succeed for non-artifact paths
        let result = std::panic::catch_unwind(|| {
            check_io_allowed(&path, "write");
        });
        assert!(result.is_ok(), "Non-artifact paths should always be allowed");
    }
}