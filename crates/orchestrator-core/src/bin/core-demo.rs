use orchestrator_core::{OrchestratorCore, mocks::{MockRouter, MockExecutor, ChannelOutbound}};
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    // Wire mocks
    let router = MockRouter;
    let executor = MockExecutor;
    let (tx, mut rx) = mpsc::channel(16);
    let outbound = ChannelOutbound(tx);
    let mut core = OrchestratorCore::new(router, executor, outbound);

    // Parse args
    let mut args = std::env::args().skip(1).collect::<Vec<_>>();
    if let Some(pos) = args.iter().position(|a| a == "--no-confirm") { args.remove(pos); core.set_require_confirmation(false); }
    // Build a user_text message from remaining args or default
    let text = args.join(" ");
    let text = if text.is_empty() { "please refactor the module".to_string() } else { text };

    let msg = protocol::Message::user_text(text, Some("demo".to_string()), true);
    if let Err(e) = core.handle(msg).await { eprintln!("error: {}", e); }

    // Drain and print outbound messages as JSON
    while let Ok(msg) = rx.try_recv() {
        let s = serde_json::to_string_pretty(&msg).unwrap_or_default();
        println!("{}", s);
    }
}
