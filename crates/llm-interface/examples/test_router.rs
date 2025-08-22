use llm_interface::{LLMProvider, GroqProvider};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load .env
    dotenv::from_path(".env").ok();
    
    // Initialize provider
    let mut provider = GroqProvider::new();
    provider.initialize(serde_json::json!({})).await?;
    
    // Test various commands
    let test_commands = vec![
        "Fix the bug in the authentication system",
        "Write a Python script to process CSV files",
        "What's the weather today?",
        "Hello",
    ];
    
    for cmd in test_commands {
        println!("\nTesting: {}", cmd);
        let response = provider.text_to_plan(cmd).await?;
        println!("Response: {}", response);
    }
    
    Ok(())
}