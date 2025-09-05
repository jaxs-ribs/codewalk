// Test to verify the core-to-app channel works
use tokio::sync::mpsc;
use std::sync::Arc;

#[tokio::main]
async fn main() {
    println!("Testing channel communication...\n");
    
    // Create the same channel setup as in core_bridge
    let (out_tx, mut out_rx) = mpsc::channel::<String>(100);
    
    // Simulate the core sending messages
    let sender = Arc::new(out_tx);
    
    // Spawn a task to send messages (simulating core)
    let sender_clone = sender.clone();
    tokio::spawn(async move {
        println!("Sender: Sending test messages...");
        for i in 1..=5 {
            let msg = format!("Message {}", i);
            println!("Sender: Sending '{}'", msg);
            if let Err(e) = sender_clone.send(msg).await {
                println!("Sender: Error sending: {}", e);
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        }
        println!("Sender: Done sending");
    });
    
    // Simulate poll_core_outbound
    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    
    println!("\nReceiver: Polling for messages...");
    for _ in 0..10 {
        let mut buffered = Vec::new();
        for _ in 0..50 {
            match out_rx.try_recv() {
                Ok(msg) => {
                    println!("Receiver: Got '{}'", msg);
                    buffered.push(msg);
                }
                Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                    println!("Receiver: Channel disconnected!");
                    return;
                }
            }
        }
        
        if !buffered.is_empty() {
            println!("Receiver: Processed {} messages", buffered.len());
        }
        
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
    
    println!("\nTest complete!");
}