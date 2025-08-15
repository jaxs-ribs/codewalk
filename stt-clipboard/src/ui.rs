use std::io::{stdout, Write};
use anyhow::Result;

pub fn print_welcome() {
    println!("\n🎤 STT-Clipboard");
    println!("━━━━━━━━━━━━━━━━");
    println!("Press SPACE to start/stop recording");
    println!("Press Q to quit\n");
}

pub fn print_goodbye() {
    println!("\nGoodbye!");
}

pub fn show_recording() -> Result<()> {
    print!("\r🔴 Recording... (press SPACE to stop)");
    flush_output()
}

pub fn show_processing() -> Result<()> {
    print!("\r⏳ Processing...                     ");
    flush_output()
}

pub fn show_copied(text: &str) -> Result<()> {
    print!("\r\x1b[K");
    println!("✅ Copied to clipboard\n");
    println!("{}\n", text.trim());
    print!("Ready (SPACE to record, Q to quit)");
    flush_output()
}

pub fn show_no_speech() -> Result<()> {
    print!("\r\x1b[K⚠️  No speech detected. Ready (SPACE to record, Q to quit)");
    flush_output()
}

pub fn show_no_audio() -> Result<()> {
    print!("\r\x1b[K⚠️  No audio recorded. Ready (SPACE to record, Q to quit)");
    flush_output()
}

pub fn show_error(error: &str) -> Result<()> {
    print!("\r\x1b[K❌ Error: {}. Ready (SPACE to record, Q to quit)", 
        if error.len() > 20 { &error[..20] } else { error });
    flush_output()
}

fn flush_output() -> Result<()> {
    stdout().flush()?;
    Ok(())
}