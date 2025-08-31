use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;
use tokio::time::{sleep, Duration};

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [cmd, rest @ ..] if cmd == "e2e" => e2e(rest).await,
        _ => {
            eprintln!("Usage: cargo run -p xtask -- e2e [quick|full] [--text '...']");
            Ok(())
        }
    }
}

async fn e2e(args: &[String]) -> Result<()> {
    let mode = args.get(0).map(String::as_str).unwrap_or("quick");
    let text = args.iter().skip_while(|s| *s != "--text").nth(1).cloned().unwrap_or_else(|| "build a small cli tool please".to_string());

    println!("\x1b[36m[e2e]\x1b[0m Building workspace (warnings as errors)…");
    let mut build = Command::new("cargo")
        .arg("build").arg("--workspace")
        .env("RUSTFLAGS", "-D warnings")
        .stdout(Stdio::inherit()).stderr(Stdio::inherit())
        .spawn()?;
    let status = build.wait().await?;
    if !status.success() { anyhow::bail!("build failed"); }

    // Load .env to get RELAY_WS_URL, RELAY_SESSION_ID, RELAY_TOKEN
    let root = workspace_root()?;
    let env_path = root.join(".env");
    let env = std::fs::read_to_string(&env_path).context("read .env")?;
    let ws = get_env(&env, "RELAY_WS_URL")?;
    let sid = get_env(&env, "RELAY_SESSION_ID")?;
    let tok = get_env(&env, "RELAY_TOKEN")?;

    // Spawn relay server
    println!("\x1b[36m[e2e]\x1b[0m Starting relay-server at {}…", &ws);
    let mut relay = Command::new("cargo")
        .arg("run").arg("-p").arg("relay-server")
        .stdout(Stdio::inherit()).stderr(Stdio::inherit())
        .spawn().context("spawn relay-server")?;

    // Wait for health
    let health = ws_to_health(&ws);
    println!("\x1b[36m[e2e]\x1b[0m Waiting for relay health: {}", &health);
    wait_health(&health, Duration::from_secs(20)).await.context("relay health")?;

    // Spawn headless orchestrator
    println!("\x1b[36m[e2e]\x1b[0m Starting orchestrator (headless)…");
    let mut orch = Command::new("cargo")
        .arg("run").arg("-p").arg("orchestrator").arg("--no-default-features")
        .env("RUSTFLAGS", "-A warnings")
        .env("RELAY_WS_URL", &ws)
        .env("RELAY_SESSION_ID", &sid)
        .env("RELAY_TOKEN", &tok)
        .stdout(Stdio::inherit()).stderr(Stdio::inherit())
        .spawn().context("spawn orchestrator")?;

    // Small delay for websocket to connect
    println!("\x1b[36m[e2e]\x1b[0m Giving orchestrator time to connect…");
    sleep(Duration::from_millis(700)).await;

    // Run phone-bot (sends user_text and waits for ack)
    println!("\x1b[36m[e2e]\x1b[0m Running phone-bot with text: {}", &text);
    let status = Command::new("cargo")
        .arg("run").arg("-p").arg("relay-client-mobile")
        .arg("--bin").arg("relay-phone-bot")
        .env("RUSTFLAGS", "-A warnings")
        .env("RELAY_WS_URL", &ws)
        .env("RELAY_SESSION_ID", &sid)
        .env("RELAY_TOKEN", &tok)
        .env("BOT_TEXT", &text)
        .status().await.context("run phone-bot")?;

    let ok = status.success();
    if !ok { cleanup(&mut relay, &mut orch).await; anyhow::bail!("phone-bot failed"); }

    if mode == "full" {
        // Spawn a waiter that connects and waits for session-killed
        println!("\x1b[36m[e2e]\x1b[0m Spawning phone-bot waiter for session-killed…");
        let mut waiter = Command::new("cargo")
            .arg("run").arg("-p").arg("relay-client-mobile")
            .arg("--bin").arg("relay-phone-bot")
            .env("RUSTFLAGS", "-A warnings")
            .env("RELAY_WS_URL", &ws)
            .env("RELAY_SESSION_ID", &sid)
            .env("RELAY_TOKEN", &tok)
            .env("BOT_WAIT_KILL", "1")
            .stdout(Stdio::inherit()).stderr(Stdio::inherit())
            .spawn().context("spawn waiter")?;
        sleep(Duration::from_millis(800)).await;
        let kill_url = format!("http://{}/api/session/{}", ws_to_http_host(&ws), sid);
        println!("\x1b[36m[e2e]\x1b[0m Killing session via {}", &kill_url);
        let resp = reqwest::Client::new().delete(kill_url).send().await?;
        if resp.status() != 204 { eprintln!("warn: kill session status {}", resp.status()); }
        let status = waiter.wait().await?;
        if !status.success() { cleanup(&mut relay, &mut orch).await; anyhow::bail!("waiter did not observe session-killed"); }
    }

    cleanup(&mut relay, &mut orch).await;
    println!("\x1b[32mE2E({}) PASS\x1b[0m", mode);
    Ok(())
}

async fn cleanup(relay: &mut tokio::process::Child, orch: &mut tokio::process::Child) {
    let _ = relay.start_kill();
    let _ = orch.start_kill();
}

fn workspace_root() -> Result<PathBuf> {
    let cwd = std::env::current_dir()?;
    Ok(cwd)
}

fn get_env(env: &str, key: &str) -> Result<String> {
    for line in env.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        if let Some((k, v)) = line.split_once('=') {
            if k.trim() == key { return Ok(v.trim().trim_matches('"').trim_matches('\'').to_string()); }
        }
    }
    anyhow::bail!("{} not found in .env", key)
}

fn ws_to_health(ws: &str) -> String {
    let http = ws.replace("wss://", "http://").replace("ws://", "http://");
    http.trim_end_matches("/ws").to_string() + "/health"
}

fn ws_to_http_host(ws: &str) -> String {
    ws.replace("wss://", "").replace("ws://", "").trim_end_matches("/ws").to_string()
}

async fn wait_health(url: &str, timeout_total: Duration) -> Result<()> {
    let client = reqwest::Client::new();
    let start = tokio::time::Instant::now();
    loop {
        if start.elapsed() > timeout_total { anyhow::bail!("timeout waiting health"); }
        match client.get(url).send().await {
            Ok(r) if r.status().is_success() => return Ok(()),
            _ => sleep(Duration::from_millis(300)).await,
        }
    }
}
