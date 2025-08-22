use llm_interface::{LLMProvider, GroqProvider};
use std::time::Instant;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load .env
    dotenv::from_path(".env").ok();
    
    // Initialize provider with Kimi K2
    let mut provider = GroqProvider::new();
    provider.initialize(serde_json::json!({})).await?;
    
    println!("Using Kimi K2 with prompt caching...\n");
    
    // Test various commands - the system prompt will be cached after first call
    let test_commands = vec![
        "Fix the bug in the authentication system",
        "Write a Python script to process CSV files",
        "Help me refactor this React component to use hooks",
        "What's the weather today?",
        "Hello",
        "Create a REST API with Express.js",
    ];
    
    // First call will cache the system prompt
    println!("First call (caches system prompt):");
    let start = Instant::now();
    let response = provider.text_to_plan(&test_commands[0]).await?;
    let first_duration = start.elapsed();
    println!("  Command: {}", test_commands[0]);
    println!("  Response: {}", response);
    println!("  Time: {:?}", first_duration);
    
    // Subsequent calls should be faster due to prompt caching
    println!("\nSubsequent calls (using cached prompt):");
    for cmd in &test_commands[1..] {
        let start = Instant::now();
        let response = provider.text_to_plan(cmd).await?;
        let duration = start.elapsed();
        println!("\n  Command: {}", cmd);
        println!("  Response: {}", response);
        println!("  Time: {:?} ({}% of first call)", 
                 duration, 
                 (duration.as_millis() * 100 / first_duration.as_millis()));
    }
    
    Ok(())
}