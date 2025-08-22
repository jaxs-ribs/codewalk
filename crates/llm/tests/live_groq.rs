use llm::{Client, Role, ChatMessage, ChatOptions};
use std::time::Instant;

fn init_env() {
    // Load .env from workspace root (two levels up from tests)
    let _ = dotenv::from_path("../../.env");
}

#[tokio::test]
async fn test_kimi_k2() {
    init_env();
    println!("\n=== Testing Kimi K2 Model ===");
    let cli = Client::from_env_groq("moonshotai/kimi-k2-instruct").unwrap();
    let out = cli.simple("Reply with exactly: Hello from Kimi").await.unwrap();
    println!("Kimi K2 Response: {}", out);
    assert!(!out.trim().is_empty());
}

#[tokio::test]
async fn basic_call() {
    init_env();
    println!("\n=== Testing Basic Call (Llama 3.1) ===");
    let cli = Client::from_env_groq("llama-3.1-8b-instant").unwrap();
    let out = cli.simple("Say OK.").await.unwrap();
    println!("Response: {}", out);
    assert!(!out.trim().is_empty());
}

#[tokio::test]
async fn latency_avg_ms() {
    init_env();
    println!("\n=== Testing Latency (5 runs) ===");
    let cli = Client::from_env_groq("llama-3.1-8b-instant").unwrap();

    // warm
    println!("Warming up...");
    let _ = cli.simple("warm").await.unwrap();

    let runs = 5;
    let mut total = 0u128;
    let mut times = Vec::new();
    for i in 0..runs {
        let t0 = Instant::now();
        let _ = cli.simple("one short sentence").await.unwrap();
        let elapsed = t0.elapsed().as_millis();
        times.push(elapsed);
        total += elapsed;
        println!("Run {}: {}ms", i + 1, elapsed);
    }
    println!("Average latency: {:.1}ms", total as f64 / runs as f64);
}

#[tokio::test]
async fn json_object_mode() {
    init_env();
    println!("\n=== Testing JSON Object Mode ===");
    let cli = Client::from_env_groq("llama-3.1-8b-instant").unwrap();
    let msgs = vec![
        ChatMessage{ role: Role::System, content: "Reply ONLY as valid JSON with a field 'ok': true".into() },
        ChatMessage{ role: Role::User, content: "ack".into() }
    ];
    let out = cli.chat(&msgs, ChatOptions{ json_object: true, temperature: Some(0.0) }).await.unwrap();
    println!("JSON Response: {}", out);
    // Should parse as JSON
    let v: serde_json::Value = serde_json::from_str(&out).unwrap();
    assert_eq!(v.get("ok").and_then(|x| x.as_bool()), Some(true));
    println!("✓ Valid JSON with ok=true");
}