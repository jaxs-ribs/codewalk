use anyhow::Result;
use router::providers::groq::GroqProvider;
use router::traits::LLMProvider;

#[tokio::main]
async fn main() -> Result<()> {
    // Load .env from workspace root
    dotenv::from_path(".env").ok();
    
    // Show which model we're using
    let model = std::env::var("GROQ_MODEL")
        .unwrap_or_else(|_| "llama-3.1-8b-instant (default)".to_string());
    println!("Testing with model: {}", model);
    
    // Initialize Groq provider
    let mut provider = GroqProvider::new();
    provider.initialize(serde_json::Value::Null).await?;
    
    // Test voice command routing
    let test_commands = vec![
        "Help me fix this bug in my code",
        "What's the weather today?",
        "Write a Python script to parse JSON",
    ];
    
    for cmd in test_commands {
        println!("\nCommand: \"{}\"", cmd);
        let start = std::time::Instant::now();
        
        match provider.text_to_plan(cmd).await {
            Ok(response) => {
                let elapsed = start.elapsed();
                println!("Response ({}ms): {}", elapsed.as_millis(), response);
            }
            Err(e) => {
                println!("Error: {}", e);
            }
        }
    }
    
    Ok(())
}