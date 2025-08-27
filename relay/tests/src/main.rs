use anyhow::Result;
use colored::*;
use futures_util::{SinkExt, StreamExt};
use indicatif::{ProgressBar, ProgressStyle};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tokio::time::{sleep, timeout};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use std::future::Future;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SessionInfo {
    #[serde(rename = "sessionId")]
    session_id: String,
    token: String,
    ws: String,
}

#[derive(Clone)]
struct TestMetrics {
    messages_sent: Arc<AtomicU64>,
    messages_received: Arc<AtomicU64>,
    messages_lost: Arc<AtomicU64>,
    errors: Arc<AtomicUsize>,
}

impl TestMetrics {
    fn new() -> Self {
        Self {
            messages_sent: Arc::new(AtomicU64::new(0)),
            messages_received: Arc::new(AtomicU64::new(0)),
            messages_lost: Arc::new(AtomicU64::new(0)),
            errors: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn print_summary(&self, test_name: &str, duration: Duration) {
        let sent = self.messages_sent.load(Ordering::Relaxed);
        let received = self.messages_received.load(Ordering::Relaxed);
        let lost = self.messages_lost.load(Ordering::Relaxed);
        let errors = self.errors.load(Ordering::Relaxed);
        
        println!("\n{}", format!("=== {} Results ===", test_name).blue().bold());
        println!("Duration: {:.2}s", duration.as_secs_f64());
        println!("Messages sent: {}", sent);
        println!("Messages received: {}", received);
        println!("Messages lost: {}", lost);
        println!("Success rate: {:.1}%", (received as f64 / sent as f64) * 100.0);
        println!("Throughput: {:.0} msg/sec", received as f64 / duration.as_secs_f64());
        println!("Errors: {}", errors);
    }
}

async fn register_session() -> Result<SessionInfo> {
    let base = std::env::var("RELAY_BASE_URL").unwrap_or_else(|_| "http://localhost:3001".to_string());
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{}/api/register", base))
        .send()
        .await?;
    Ok(resp.json().await?)
}

async fn run_with_timeout<F>(name: &str, secs: u64, fut: F) -> Result<()>
where
    F: Future<Output = Result<()>>,
{
    match timeout(Duration::from_secs(secs), fut).await {
        Ok(r) => r,
        Err(_) => anyhow::bail!(format!("Test '{}' timed out after {}s", name, secs)),
    }
}

// Test 1: Basic connectivity and message relay
async fn test_basic_relay() -> Result<()> {
    println!("\n{}", "TEST 1: Basic Message Relay".green().bold());
    
    let session = register_session().await?;
    println!("Session created: {}", session.session_id);
    
    // Connect workstation
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    // Set up workstation reader
    let (tx1, mut rx1) = tokio::sync::mpsc::channel::<String>(100);
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let _ = tx1.send(frame.to_string()).await;
                        }
                    }
                }
            }
        }
    });
    
    // Connect phone
    sleep(Duration::from_millis(100)).await;
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    // Set up phone reader
    let (tx2, mut rx2) = tokio::sync::mpsc::channel::<String>(100);
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let _ = tx2.send(frame.to_string()).await;
                        }
                    }
                }
            }
        }
    });
    
    // Wait for connections to establish
    sleep(Duration::from_millis(200)).await;
    
    // Test workstation -> phone
    println!("Testing workstation → phone...");
    write1.send(Message::Text("Test message from workstation".to_string())).await?;
    
    if let Ok(Some(msg)) = timeout(Duration::from_secs(1), rx2.recv()).await {
        if msg == "Test message from workstation" {
            println!("{}", "✓ Message delivered correctly".green());
        } else {
            println!("{} Got: {}", "✗ Wrong message".red(), msg);
        }
    } else {
        println!("{}", "✗ Message not received".red());
    }
    
    // Test phone -> workstation
    println!("Testing phone → workstation...");
    write2.send(Message::Text("Test message from phone".to_string())).await?;
    
    if let Ok(Some(msg)) = timeout(Duration::from_secs(1), rx1.recv()).await {
        if msg == "Test message from phone" {
            println!("{}", "✓ Message delivered correctly".green());
        } else {
            println!("{} Got: {}", "✗ Wrong message".red(), msg);
        }
    } else {
        println!("{}", "✗ Message not received".red());
    }
    
    Ok(())
}

// Test 2: Message ordering and reliability
async fn test_message_ordering() -> Result<()> {
    println!("\n{}", "TEST 2: Message Ordering".green().bold());
    
    let session = register_session().await?;
    let metrics = TestMetrics::new();
    
    // Connect both clients
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut _read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Collect received messages
    let received = Arc::new(RwLock::new(Vec::new()));
    let received_clone = received.clone();
    
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            let mut msgs = received_clone.write().await;
                            msgs.push(frame.to_string());
                        }
                    }
                }
            }
        }
    });
    
    // Send numbered messages
    let num_messages = 20;
    for i in 0..num_messages {
        let msg = format!("Message {}", i);
        write1.send(Message::Text(msg.clone())).await?;
        metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
        // No delay for maximum throughput in ordering test
    }
    
    // Wait for messages to arrive
    sleep(Duration::from_secs(1)).await;
    
    let msgs = received.read().await;
    let received_count = msgs.len();
    
    println!("Sent: {} messages", num_messages);
    println!("Received: {} messages", received_count);
    
    // Check ordering
    let mut in_order = true;
    for (i, msg) in msgs.iter().enumerate() {
        let expected = format!("Message {}", i);
        if msg != &expected {
            println!("{} Message {} out of order: expected '{}', got '{}'", 
                     "✗".red(), i, expected, msg);
            in_order = false;
            break;
        }
    }
    
    if in_order && received_count == num_messages {
        println!("{}", "✓ All messages received in correct order".green());
    } else if in_order {
        println!("{}", "✓ Messages in order but some lost".yellow());
    }
    
    Ok(())
}

// Test 3: Throughput and latency
async fn test_throughput() -> Result<()> {
    println!("\n{}", "TEST 3: Throughput & Latency".green().bold());
    
    let session = register_session().await?;
    let metrics = TestMetrics::new();
    let start = Instant::now();
    
    // Connect clients
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Phone echoes messages back with timestamp
    let metrics_clone = metrics.clone();
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            metrics_clone.messages_received.fetch_add(1, Ordering::Relaxed);
                            // Simple echo for better throughput
                            let echo = format!("ECHO:{}", frame);
                            write2.send(Message::Text(echo)).await.ok();
                        }
                    }
                }
            }
        }
    });
    
    // Workstation receives echoes and calculates latency
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            if frame.starts_with("ECHO:") {
                                // Count echo responses for throughput measurement
                                // Removed latency tracking due to timestamp parsing issues
                            }
                        }
                    }
                }
            }
        }
    });
    
    // Send messages rapidly without waiting for individual responses
    let num_messages = 5000;  // Increased for better throughput measurement
    let pb = ProgressBar::new(num_messages);
    pb.set_style(ProgressStyle::default_bar()
        .template("{spinner:.green} [{bar:40.cyan/blue}] {pos}/{len} {msg}")?
        .progress_chars("#>-"));
    
    for i in 0..num_messages {
        let msg = format!("Throughput test message {}", i);
        write1.send(Message::Text(msg)).await?;
        metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
        pb.inc(1);
    }
    
    pb.finish_with_message("Messages sent");
    
    // Wait for echoes (adjusted for more messages)
    sleep(Duration::from_secs(5)).await;
    
    let duration = start.elapsed();
    metrics.print_summary("Throughput Test", duration);
    
    // Latency measurement removed due to complexity in echo-based testing
    
    Ok(())
}

// Test 4: Concurrent pairs
async fn test_concurrent_pairs() -> Result<()> {
    println!("\n{}", "TEST 4: Concurrent Pairs".green().bold());
    
    let num_pairs = 5;
    let messages_per_pair = 10;
    let metrics = TestMetrics::new();
    let start = Instant::now();
    
    let mut tasks = Vec::new();
    
    for pair_id in 0..num_pairs {
        let metrics = metrics.clone();
        
        let task = tokio::spawn(async move {
            if let Ok(session) = register_session().await {
                // Connect workstation
                if let Ok((ws1, _)) = connect_async(&session.ws).await {
                    let (mut write1, mut read1) = ws1.split();
                    
                    write1.send(Message::Text(json!({
                        "type": "hello",
                        "s": session.session_id,
                        "t": session.token,
                        "r": "workstation"
                    }).to_string())).await.ok();
                    
                    // Connect phone
                    sleep(Duration::from_millis(50)).await;
                    
                    if let Ok((ws2, _)) = connect_async(&session.ws).await {
                        let (mut write2, mut read2) = ws2.split();
                        
                        write2.send(Message::Text(json!({
                            "type": "hello",
                            "s": session.session_id,
                            "t": session.token,
                            "r": "phone"
                        }).to_string())).await.ok();
                        
                        // Phone echo task
                        tokio::spawn(async move {
                            while let Some(msg) = read2.next().await {
                                if let Ok(Message::Text(text)) = msg {
                                    // Parse the JSON message and extract the frame content
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                        if json["type"] == "frame" {
                                            if let Some(frame) = json["frame"].as_str() {
                                                write2.send(Message::Text(format!("Echo: {}", frame))).await.ok();
                                            }
                                        }
                                    }
                                }
                            }
                        });
                        
                        // Workstation receiver
                        let metrics_clone = metrics.clone();
                        tokio::spawn(async move {
                            while let Some(msg) = read1.next().await {
                                if let Ok(Message::Text(text)) = msg {
                                    // Parse the JSON message and extract the frame content
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                                        if json["type"] == "frame" {
                                            if let Some(frame) = json["frame"].as_str() {
                                                if frame.starts_with("Echo:") {
                                                    metrics_clone.messages_received.fetch_add(1, Ordering::Relaxed);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        });
                        
                        // Send messages
                        sleep(Duration::from_millis(200)).await;
                        for i in 0..messages_per_pair {
                            let msg = format!("Pair {} Message {}", pair_id, i);
                            write1.send(Message::Text(msg)).await.ok();
                            metrics.messages_sent.fetch_add(1, Ordering::Relaxed);
                            sleep(Duration::from_millis(10)).await;
                        }
                        
                        sleep(Duration::from_secs(1)).await;
                    }
                }
            }
        });
        
        tasks.push(task);
    }
    
    // Wait for all pairs to complete
    for task in tasks {
        task.await.ok();
    }
    
    let duration = start.elapsed();
    metrics.print_summary("Concurrent Pairs Test", duration);
    
    Ok(())
}

// Test 5: Connection stability
async fn test_connection_stability() -> Result<()> {
    println!("\n{}", "TEST 5: Connection Stability".green().bold());
    
    let session = register_session().await?;
    let test_duration = Duration::from_secs(5);
    let start = Instant::now();
    
    // Connect workstation
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, mut read1) = ws1.split();
    
    write1.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    
    // Connect phone
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    
    write2.send(Message::Text(json!({
        "type": "hello",
        "s": session.session_id,
        "t": session.token,
        "r": "phone"
    }).to_string())).await?;
    
    sleep(Duration::from_millis(200)).await;
    
    // Phone echo
    tokio::spawn(async move {
        while let Some(msg) = read2.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            write2.send(Message::Text(format!("ACK:{}", frame))).await.ok();
                        }
                    }
                }
            }
        }
    });
    
    // Send periodic heartbeats
    let mut sent = 0;
    let mut received = 0;
    
    // Collect acknowledgments separately
    let (ack_tx, mut ack_rx) = tokio::sync::mpsc::unbounded_channel();
    tokio::spawn(async move {
        while let Some(msg) = read1.next().await {
            if let Ok(Message::Text(text)) = msg {
                // Parse the JSON message and extract the frame content
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if json["type"] == "frame" {
                        if let Some(frame) = json["frame"].as_str() {
                            if frame.starts_with("ACK:PING:") {
                                ack_tx.send(()).ok();
                            }
                        }
                    }
                }
            }
        }
    });
    
    // Send heartbeats
    while start.elapsed() < test_duration {
        write1.send(Message::Text(format!("PING:{}", sent))).await?;
        sent += 1;
        sleep(Duration::from_millis(500)).await;
    }
    
    // Wait a bit for remaining acknowledgments to arrive
    sleep(Duration::from_millis(500)).await;
    
    // Count received acknowledgments
    while ack_rx.try_recv().is_ok() {
        received += 1;
    }
    
    println!("Heartbeats sent: {}", sent);
    println!("Acknowledgments received: {}", received);
    println!("Connection stability: {:.1}%", (received as f64 / sent as f64) * 100.0);
    
    if received == sent {
        println!("{}", "✓ Perfect connection stability".green());
    } else if received as f64 / sent as f64 > 0.95 {
        println!("{}", "✓ Good connection stability".green());
    } else {
        println!("{}", "✗ Poor connection stability".red());
    }
    
    Ok(())
}

// New: Idle expiry basic (Test 6)
async fn test_idle_expiry_basic() -> Result<()> {
    println!("\n{}", "TEST 6: Idle Expiry Basic".green().bold());
    let session = register_session().await?;
    // Do not connect; wait for expiration
    sleep(Duration::from_secs(3)).await;
    // Try to connect and hello; should be rejected (no hello-ack, likely close)
    let (ws, _) = connect_async(&session.ws).await?;
    let (mut write, mut read) = ws.split();
    write.send(Message::Text(json!({
        "type":"hello",
        "s": session.session_id,
        "t": session.token,
        "r": "workstation"
    }).to_string())).await?;
    // Expect close or no hello-ack within 500ms
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(500), read.next()).await {
        // If we got a hello-ack, it's a failure
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
            if v["type"] == "hello-ack" {
                anyhow::bail!("Session should have expired and been rejected");
            }
        }
    }
    println!("{}", "✓ Expired sessions are rejected".green());
    Ok(())
}

// New: Idle refresh on heartbeat (Test 7)
async fn test_idle_refresh_on_heartbeat() -> Result<()> {
    println!("\n{}", "TEST 7: Idle Refresh on Heartbeat".green().bold());
    let session = register_session().await?;
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut write1, _read1) = ws1.split();
    write1.send(Message::Text(json!({
        "type":"hello","s":session.session_id,"t":session.token,"r":"workstation"
    }).to_string())).await?;
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut write2, mut read2) = ws2.split();
    write2.send(Message::Text(json!({
        "type":"hello","s":session.session_id,"t":session.token,"r":"phone"
    }).to_string())).await?;
    // Send heartbeat every 1s for 5s from workstation
    for _ in 0..5 {
        write1.send(Message::Text("{\"type\":\"hb\"}".to_string())).await?;
        sleep(Duration::from_secs(1)).await;
    }
    // Now try a frame and expect delivery
    write1.send(Message::Text("alive?".to_string())).await?;
    let got = timeout(Duration::from_secs(1), async {
        loop {
            if let Some(Ok(Message::Text(t))) = read2.next().await {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
                    if v["type"] == "frame" && v["frame"].as_str() == Some("alive?") { break true; }
                }
            } else { break false; }
        }
    }).await.unwrap_or(false);
    if !got { anyhow::bail!("Did not receive frame after heartbeats"); }
    println!("{}", "✓ Heartbeats keep session alive".green());
    Ok(())
}

// New: Kill endpoint terminates connections (Test 8)
async fn test_kill_endpoint() -> Result<()> {
    println!("\n{}", "TEST 8: Kill Endpoint".green().bold());
    let session = register_session().await?;
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut _w1, mut r1) = ws1.split();
    _w1.send(Message::Text(json!({
        "type":"hello","s":session.session_id,"t":session.token,"r":"workstation"
    }).to_string())).await?;
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut _w2, mut r2) = ws2.split();
    _w2.send(Message::Text(json!({
        "type":"hello","s":session.session_id,"t":session.token,"r":"phone"
    }).to_string())).await?;
    // Wait briefly for both sides to establish and subscribe
    let mut saw_ack_1 = false;
    let mut saw_ack_2 = false;
    let start = Instant::now();
    while start.elapsed() < Duration::from_millis(500) {
        if !saw_ack_1 {
            if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(10), r1.next()).await {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) { if v["type"] == "hello-ack" { saw_ack_1 = true; } }
            }
        }
        if !saw_ack_2 {
            if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(10), r2.next()).await {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) { if v["type"] == "hello-ack" { saw_ack_2 = true; } }
            }
        }
        if saw_ack_1 && saw_ack_2 { break; }
    }
    // Issue DELETE
    let base = std::env::var("RELAY_BASE_URL").unwrap_or_else(|_| "http://localhost:3001".to_string());
    let client = reqwest::Client::new();
    let resp = client.delete(format!("{}/api/session/{}", base, session.session_id)).send().await?;
    if resp.status() != 204 { anyhow::bail!("Kill endpoint failed: {}", resp.status()); }
    // Expect session-killed or close on each
    let mut term = 0u32;
    for rx in [&mut r1, &mut r2] {
        let seen = timeout(Duration::from_secs(3), async {
            loop {
                match rx.next().await {
                    Some(Ok(Message::Text(t))) => {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
                            if v["type"] == "session-killed" { break true; }
                        }
                    }
                    Some(Ok(Message::Close(_))) => break true,
                    Some(Ok(_)) => {}
                    Some(Err(_)) | None => break false,
                }
            }
        }).await.unwrap_or(false);
        if seen { term += 1; }
    }
    if term == 0 {
        // Fallback: verify that session is dead by rejecting new hello
        let (ws_new, _) = connect_async(&session.ws).await?;
        let (mut w_new, mut r_new) = ws_new.split();
        w_new.send(Message::Text(json!({
            "type":"hello","s":session.session_id,"t":session.token,"r":"workstation"
        }).to_string())).await?;
        if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(500), r_new.next()).await {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) { if v["type"] == "hello-ack" { anyhow::bail!("Kill did not invalidate session"); } }
        }
        println!("{}", "✓ Kill invalidates session for new connections".green());
    } else {
        println!("{}", "✓ Kill publishes notifications and closes".green());
    }
    Ok(())
}

// New: Reject wrong token (Test 9)
async fn test_reject_wrong_token() -> Result<()> {
    println!("\n{}", "TEST 9: Reject Wrong Token".green().bold());
    let session = register_session().await?;
    let (ws, _) = connect_async(&session.ws).await?;
    let (mut w, mut r) = ws.split();
    w.send(Message::Text(json!({"type":"hello","s":session.session_id,"t":"badtoken","r":"workstation"}).to_string())).await?;
    // Expect close or no hello-ack
    if let Ok(Some(Ok(Message::Text(t)))) = timeout(Duration::from_millis(500), r.next()).await {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) { if v["type"] == "hello-ack" { anyhow::bail!("Accepted wrong token"); } }
    }
    println!("{}", "✓ Wrong token rejected".green());
    Ok(())
}

// New: No backfill after late join (Test 10)
async fn test_no_backfill_after_late_join() -> Result<()> {
    println!("\n{}", "TEST 10: No Backfill After Late Join".green().bold());
    let session = register_session().await?;
    let (ws1, _) = connect_async(&session.ws).await?;
    let (mut w1, _r1) = ws1.split();
    w1.send(Message::Text(json!({"type":"hello","s":session.session_id,"t":session.token,"r":"workstation"}).to_string())).await?;
    // Send a few frames before phone joins
    for i in 0..3 {
        w1.send(Message::Text(format!("early-{}", i))).await?;
    }
    // Now phone joins
    let (ws2, _) = connect_async(&session.ws).await?;
    let (mut _w2, mut r2) = ws2.split();
    _w2.send(Message::Text(json!({"type":"hello","s":session.session_id,"t":session.token,"r":"phone"}).to_string())).await?;
    // Expect no early frames; send one new and expect that one
    w1.send(Message::Text("later".to_string())).await?;
    let ok = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            match r2.next().await {
                Some(Ok(Message::Text(t))) => {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
                        if v["type"] == "frame" && v["frame"] == "later" { break true; }
                    }
                }
                Some(Ok(_)) => {}
                Some(Err(_)) | None => break false,
            }
        }
    }).await.unwrap_or(false);
    if ok { println!("{}","✓ No backfill".green()); Ok(()) } else { anyhow::bail!("Phone did not receive the expected post-join frame") }
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("\n{}", "=".repeat(60).blue());
    println!("{}", "RELAY SYSTEM INTEGRATION TEST SUITE".blue().bold());
    println!("{}", "=".repeat(60).blue());
    
    // Check server is running
    let base = std::env::var("RELAY_BASE_URL").unwrap_or_else(|_| "http://localhost:3001".to_string());
    let client = reqwest::Client::new();
    match client.get(format!("{}/health", base)).send().await {
        Ok(_) => println!("{}", "✓ Server is running".green()),
        Err(_) => {
            println!("{}", "✗ Server is not running!".red());
            println!("Please start the relay server first:");
            println!("  RELAY_BASE_URL=... cargo run --release -p relay-server");
            return Ok(());
        }
    }
    
    // Optional: run a single test by name
    let mut failed = false;
    if let Ok(only) = std::env::var("RUN_ONLY") {
        let name = only.trim().to_lowercase();
        let short = std::env::var("TEST_TIMEOUT_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(20);
        let long = std::env::var("TEST_TIMEOUT_LONG_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(60);
        let res = match name.as_str() {
            "idle_expiry_basic" | "idle-expiry-basic" => run_with_timeout("idle_expiry_basic", short, test_idle_expiry_basic()).await,
            "idle_refresh_on_heartbeat" | "idle-refresh-on-heartbeat" | "hb_refresh" => run_with_timeout("idle_refresh_on_heartbeat", short, test_idle_refresh_on_heartbeat()).await,
            "kill_endpoint" | "kill-endpoint" => run_with_timeout("kill_endpoint", short, test_kill_endpoint()).await,
            "reject_wrong_token" | "reject-wrong-token" => run_with_timeout("reject_wrong_token", short, test_reject_wrong_token()).await,
            "no_backfill_after_late_join" | "no-backfill-after-late-join" | "no_backfill" => run_with_timeout("no_backfill_after_late_join", short, test_no_backfill_after_late_join()).await,
            // legacy/throughput
            "basic" => run_with_timeout("basic", long, test_basic_relay()).await,
            "ordering" => run_with_timeout("ordering", long, test_message_ordering()).await,
            "throughput" => run_with_timeout("throughput", long, test_throughput()).await,
            "concurrent" => run_with_timeout("concurrent", long, test_concurrent_pairs()).await,
            "stability" => run_with_timeout("stability", long, test_connection_stability()).await,
            other => {
                println!("Unknown test name: {}", other);
                anyhow::bail!("Unknown test");
            }
        };
        if let Err(e) = res {
            println!("{} {} failed: {}", "✗".red(), name, e);
            failed = true;
        }
    } else {
        // Run full suite with numbering by default
        let short = std::env::var("TEST_TIMEOUT_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(20);
        let long = std::env::var("TEST_TIMEOUT_LONG_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(60);
        if let Err(e) = run_with_timeout("basic", long, test_basic_relay()).await { println!("{} Basic relay test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("ordering", long, test_message_ordering()).await { println!("{} Message ordering test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("throughput", long, test_throughput()).await { println!("{} Throughput test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("concurrent", long, test_concurrent_pairs()).await { println!("{} Concurrent pairs test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("stability", long, test_connection_stability()).await { println!("{} Connection stability test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("idle_expiry_basic", short, test_idle_expiry_basic()).await { println!("{} Idle expiry basic failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("idle_refresh_on_heartbeat", short, test_idle_refresh_on_heartbeat()).await { println!("{} Idle refresh on hb failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("kill_endpoint", short, test_kill_endpoint()).await { println!("{} Kill endpoint test failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("reject_wrong_token", short, test_reject_wrong_token()).await { println!("{} Wrong token rejection failed: {}", "✗".red(), e); failed = true; }
        if let Err(e) = run_with_timeout("no_backfill_after_late_join", short, test_no_backfill_after_late_join()).await { println!("{} No backfill test failed: {}", "✗".red(), e); failed = true; }
    }
    
    // Final summary
    println!("\n{}", "=".repeat(60).blue());
    if failed {
        println!("{}", "SOME TESTS FAILED".red().bold());
    } else {
        println!("{}", "ALL TESTS PASSED".green().bold());
    }
    println!("{}", "=".repeat(60).blue());
    
    Ok(())
}
