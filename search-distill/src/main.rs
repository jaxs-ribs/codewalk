use anyhow::{Context, Result};
use dotenv::dotenv;
use futures::future::join_all;
use log::{error, info, warn};
use reqwest::Client;
use serde::Deserialize;
use serde_json::json;
use std::collections::VecDeque;
use std::env;
use std::io::{self, Write};
use std::time::{Duration, Instant};

#[derive(Debug, Deserialize)]
struct BraveSearchResponse {
    web: Option<BraveWebResults>,
}

#[derive(Debug, Deserialize)]
struct BraveWebResults {
    results: Vec<BraveResult>,
}

#[derive(Debug, Deserialize, Clone)]
struct BraveResult {
    title: String,
    url: String,
    description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GroqResponse {
    choices: Vec<GroqChoice>,
}

#[derive(Debug, Deserialize)]
struct GroqChoice {
    message: GroqMessage,
}

#[derive(Debug, Deserialize)]
struct GroqMessage {
    content: String,
}

struct Config {
    brave_api_key: String,
    groq_api_key: String,
    result_count: u32,
    fetch_timeout_ms: u64,
    model_id: String,
}

impl Config {
    fn from_env() -> Result<Self> {
        Ok(Config {
            brave_api_key: env::var("BRAVE_API_KEY")
                .context("Missing BRAVE_API_KEY environment variable")?,
            groq_api_key: env::var("GROQ_API_KEY")
                .context("Missing GROQ_API_KEY environment variable")?,
            result_count: env::var("RESULT_COUNT")
                .unwrap_or_else(|_| "8".to_string())
                .parse()
                .context("Invalid RESULT_COUNT")?,
            fetch_timeout_ms: env::var("FETCH_TIMEOUT_MS")
                .unwrap_or_else(|_| "15000".to_string())
                .parse()
                .context("Invalid FETCH_TIMEOUT_MS")?,
            model_id: env::var("MODEL_ID")
                .unwrap_or_else(|_| "moonshotai/kimi-k2-instruct-0905".to_string()),
        })
    }
}

struct FetchedPage {
    url: String,
    content: Option<String>,
}

async fn search_brave(client: &Client, query: &str, config: &Config) -> Result<Vec<BraveResult>> {
    info!("search start q=\"{}\"", query);

    let response = client
        .get("https://api.search.brave.com/res/v1/web/search")
        .header("X-Subscription-Token", &config.brave_api_key)
        .header("Accept", "application/json")
        .query(&[
            ("q", query),
            ("count", &config.result_count.to_string()),
            ("country", "us"),
            ("search_lang", "en"),
        ])
        .send()
        .await
        .context("Failed to send Brave search request")?;

    if !response.status().is_success() {
        let status = response.status();
        if status.as_u16() == 429 {
            error!("Brave API rate limit hit");
            anyhow::bail!("Brave API rate limit reached. Please wait a moment and try again.");
        }
        error!("Brave API error: {}", status);
        anyhow::bail!("Brave API returned status: {}", status);
    }

    let search_response: BraveSearchResponse = response
        .json()
        .await
        .context("Failed to parse Brave search response")?;

    let results = search_response
        .web
        .map(|w| w.results)
        .unwrap_or_default();

    info!("search results total={}", results.len());
    Ok(results)
}

async fn fetch_page(client: &Client, url: &str, timeout_ms: u64) -> FetchedPage {
    let start = std::time::Instant::now();

    let result = client
        .get(url)
        .timeout(Duration::from_millis(timeout_ms))
        .header("User-Agent", "Mozilla/5.0 (compatible; SearchDistill/1.0)")
        .send()
        .await;

    match result {
        Ok(response) if response.status().is_success() => {
            match response.text().await {
                Ok(html) => {
                    let bytes = html.len();
                    let ms = start.elapsed().as_millis();
                    info!("fetch ok url={} bytes={} ms={}", url, bytes, ms);

                    // Convert HTML to text with better formatting
                    let text = html2text::from_read(html.as_bytes(), 120);

                    // Try to find actual content by looking for paragraphs with substance
                    let lines: Vec<&str> = text.lines().collect();
                    let mut content_lines = Vec::new();
                    let mut found_content = false;

                    for line in lines.iter() {
                        let trimmed = line.trim();

                        // Skip empty lines, navigation items, and short fragments
                        if trimmed.is_empty() || trimmed.starts_with('[') || trimmed.len() < 30 {
                            continue;
                        }

                        // Look for actual sentences (containing periods, not just links)
                        if trimmed.contains(". ") || trimmed.ends_with('.') {
                            found_content = true;
                        }

                        if found_content || trimmed.len() > 50 {
                            content_lines.push(trimmed);
                            if content_lines.len() > 100 { // Get up to 100 lines of content
                                break;
                            }
                        }
                    }

                    // If we didn't find good content, fall back to original approach
                    let clean_text = if content_lines.len() > 5 {
                        content_lines.join(" ")
                    } else {
                        // Fallback: skip first 500 chars and take what we can
                        text.chars().skip(500).take(8000).collect()
                    };

                    // Ensure we have something
                    let final_text = if clean_text.len() > 100 {
                        clean_text
                    } else {
                        text.chars().take(8000).collect() // Last resort: just use raw text
                    };

                    // Log a sample of what we extracted
                    let sample: String = final_text.chars().skip(50).take(200).collect();
                    info!("Content sample from {}: {}", url, sample.replace('\n', " "));

                    FetchedPage {
                        url: url.to_string(),
                        content: Some(final_text),
                    }
                }
                Err(e) => {
                    warn!("fetch fail url={} err=read_error: {}", url, e);
                    FetchedPage {
                        url: url.to_string(),
                        content: None,
                    }
                }
            }
        }
        Ok(response) => {
            warn!("fetch fail url={} err=status_{}", url, response.status());
            FetchedPage {
                url: url.to_string(),
                content: None,
            }
        }
        Err(e) => {
            let error_type = if e.is_timeout() {
                "timeout"
            } else if e.is_connect() {
                "connection"
            } else {
                "request"
            };
            warn!("fetch fail url={} err={}", url, error_type);
            FetchedPage {
                url: url.to_string(),
                content: None,
            }
        }
    }
}

async fn fetch_concurrent(
    client: &Client,
    urls: Vec<&str>,
    timeout_ms: u64,
    concurrency: usize,
) -> Vec<FetchedPage> {
    // Limit concurrency by chunking
    let mut all_pages = Vec::new();

    for chunk in urls.chunks(concurrency) {
        let futures: Vec<_> = chunk
            .iter()
            .map(|url| fetch_page(client, url, timeout_ms))
            .collect();

        let pages = join_all(futures).await;
        all_pages.extend(pages);
    }

    all_pages
}

fn build_prompt(query: &str, results: &[BraveResult], pages: &[FetchedPage]) -> String {
    let mut prompt = format!("Query: \"{}\"\n\nSources (each: [index] title — url — snippet):\n", query);

    for (i, result) in results.iter().enumerate() {
        let index = i + 1;
        prompt.push_str(&format!("\n[{}] {} — {}\n", index, result.title, result.url));

        // Try to use fetched content first, fall back to Brave snippet
        let snippet = pages
            .iter()
            .find(|p| p.url == result.url)
            .and_then(|p| p.content.as_ref())
            .map(|s| s.clone())
            .or_else(|| result.description.clone())
            .unwrap_or_else(|| "No content available".to_string());

        // Use more content for better context (1500 chars instead of 500)
        let truncated_snippet: String = snippet.chars().take(1500).collect();

        // Clean up the snippet to remove excess whitespace
        let cleaned = truncated_snippet
            .lines()
            .map(|line| line.trim())
            .filter(|line| !line.is_empty())
            .take(20) // Limit to 20 lines
            .collect::<Vec<_>>()
            .join(" ");

        prompt.push_str(&cleaned);
        prompt.push_str("\n");
    }

    prompt
}

async fn call_groq(client: &Client, prompt: &str, config: &Config) -> Result<String> {
    let system_msg = "You summarize web search results for a voice assistant. Create a natural, conversational summary that sounds good when read aloud.

Rules:
- Write in complete, flowing sentences without citations or brackets
- Use 'about' instead of exact numbers when appropriate (e.g., 'about 30 years old' not '31-year-old')
- Spell out abbreviations on first use
- Avoid URLs, dates in numeric format, or technical notation
- Maximum 200 words for quick listening
- If information conflicts or seems unreliable, say so clearly
- Never use markdown formatting or special characters
- Write as if speaking to someone directly";

    let body = json!({
        "model": config.model_id,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.3,
        "max_tokens": 400
    });

    info!("llm call model={} prompt_chars={}", config.model_id, prompt.len());

    // Debug: log first 500 chars of prompt to see what we're sending
    let prompt_sample: String = prompt.chars().take(500).collect();
    info!("Prompt sample: {}", prompt_sample.replace('\n', " "));

    let response = client
        .post("https://api.groq.com/openai/v1/chat/completions")
        .header("Authorization", format!("Bearer {}", config.groq_api_key))
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await
        .context("Failed to send Groq request")?;

    if !response.status().is_success() {
        let status = response.status();
        let error_text = response.text().await.unwrap_or_default();

        if status.as_u16() == 429 {
            error!("Groq API rate limit hit");
            anyhow::bail!("Groq API rate limit reached. Please wait a moment and try again.");
        } else if status.as_u16() == 401 {
            error!("Groq API authentication failed");
            anyhow::bail!("Groq API authentication failed. Please check your GROQ_API_KEY.");
        }

        error!("Groq API error: {} - {}", status, error_text);
        anyhow::bail!("Groq API error: {} - {}", status, error_text);
    }

    let groq_response: GroqResponse = response
        .json()
        .await
        .context("Failed to parse Groq response")?;

    let content = groq_response
        .choices
        .into_iter()
        .next()
        .map(|c| c.message.content)
        .unwrap_or_else(|| "No response from model".to_string());

    Ok(content)
}

fn format_output(summary: &str, results: &[BraveResult]) -> String {
    let mut output = String::new();

    output.push_str("\n");
    output.push_str(&"━".repeat(80));
    output.push_str("\n\n");
    output.push_str(summary);
    output.push_str("\n\n");
    output.push_str(&"━".repeat(80));
    output.push_str("\n");

    output
}

// For voice agent integration - returns just the TTS-friendly summary
fn get_voice_summary(summary: &str) -> String {
    // Remove any markdown that might have slipped through
    summary
        .replace("##", "")
        .replace("**", "")
        .replace("*", "")
        .replace("#", "")
        .trim()
        .to_string()
}

async fn run_search_pipeline(query: String, config: &Config) -> Result<String> {
    let start_time = Instant::now();
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .build()?;

    // Step 1: Search Brave
    let search_results = match search_brave(&client, &query, &config).await {
        Ok(results) => results,
        Err(e) => {
            warn!("Brave search failed: {}", e);
            return Err(e);
        }
    };

    if search_results.is_empty() {
        return Ok("No search results found. Try different keywords.".to_string());
    }

    // Step 2: Fetch pages concurrently
    let urls: Vec<&str> = search_results.iter().map(|r| r.url.as_str()).collect();
    let pages = fetch_concurrent(&client, urls, config.fetch_timeout_ms, 4).await;

    let successful_fetches = pages.iter().filter(|p| p.content.is_some()).count();
    info!("Fetched {}/{} pages successfully", successful_fetches, pages.len());

    // If no pages fetched successfully, we can still use Brave snippets
    if successful_fetches == 0 {
        warn!("No pages could be fetched, falling back to search snippets only");
    }

    // Step 3: Build prompt
    let prompt = build_prompt(&query, &search_results, &pages);

    // Step 4: Call Groq
    let summary = call_groq(&client, &prompt, &config).await?;

    // Step 5: Format and return output
    let output = format_output(&summary, &search_results);
    let elapsed = start_time.elapsed();
    info!("done sources={} time={:.2}s", search_results.len(), elapsed.as_secs_f64());

    Ok(output)
}

struct QueryHistory {
    entries: VecDeque<String>,
    max_size: usize,
}

impl QueryHistory {
    fn new(max_size: usize) -> Self {
        Self {
            entries: VecDeque::with_capacity(max_size),
            max_size,
        }
    }

    fn add(&mut self, query: String) {
        // Don't add duplicates of the last query
        if self.entries.back() == Some(&query) {
            return;
        }

        if self.entries.len() >= self.max_size {
            self.entries.pop_front();
        }
        self.entries.push_back(query);
    }

    fn get_last(&self) -> Option<&String> {
        self.entries.back()
    }

    fn list(&self) -> Vec<String> {
        self.entries.iter().cloned().collect()
    }
}

fn print_help() {
    println!("\nSearch → Distill Interactive Shell");
    println!("{}", "━".repeat(40));
    println!("Commands:");
    println!("  <query>    - Search and summarize");
    println!("  last       - Repeat last query");
    println!("  history    - Show recent queries");
    println!("  help       - Show this help");
    println!("  clear      - Clear screen");
    println!("  quit/q     - Exit");
    println!("\nTips:");
    println!("  • Be specific with queries for better results");
    println!("  • Set RUST_LOG=info to see detailed logs");
    println!("  • Results are limited to {} sources", 8);
    println!("{}", "━".repeat(40));
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logger
    env_logger::init();

    // Load .env file
    dotenv().ok();

    // Load configuration
    let config = match Config::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            eprintln!("\n❌ Configuration error: {}", e);
            eprintln!("Make sure you have set BRAVE_API_KEY and GROQ_API_KEY in .env file");
            return Err(e);
        }
    };

    info!("Configuration loaded successfully");

    // Print welcome message
    println!("\n🔍 Search → Distill");
    println!("Interactive search and summarization tool");
    println!("Type 'help' for commands, 'quit' to exit\n");

    // Initialize history
    let mut history = QueryHistory::new(10);

    // Interactive loop
    loop {
        // Print prompt
        print!("> ");
        io::stdout().flush()?;

        // Read input
        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        let query = input.trim();

        // Handle commands
        match query.to_lowercase().as_str() {
            "" => continue,
            "quit" | "q" | "exit" => {
                println!("Goodbye!");
                break;
            }
            "help" | "?" => {
                print_help();
            }
            "clear" | "cls" => {
                print!("\x1B[2J\x1B[1;1H");
            }
            "last" => {
                if let Some(last_query) = history.get_last() {
                    println!("\n🔄 Repeating: \"{}\"", last_query);
                    println!("{}", "━".repeat(40));

                    match run_search_pipeline(last_query.clone(), &config).await {
                        Ok(output) => {
                            println!("{}", output);
                        }
                        Err(e) => {
                            // Provide user-friendly error messages
                            if e.to_string().contains("rate limit") {
                                eprintln!("\n⏱️  Rate limit reached. Please wait 30 seconds and try again.");
                            } else if e.to_string().contains("authentication") {
                                eprintln!("\n🔑 Authentication error. Please check your API keys in .env file.");
                            } else if e.to_string().contains("Failed to send") {
                                eprintln!("\n🌐 Network error. Please check your internet connection.");
                            } else {
                                eprintln!("\n❌ Error: {}", e);
                            }
                            error!("Pipeline error: {}", e);
                        }
                    }
                } else {
                    println!("No previous query to repeat.");
                }
            }
            "history" => {
                let entries = history.list();
                if entries.is_empty() {
                    println!("No query history yet.");
                } else {
                    println!("\nRecent queries:");
                    for (i, query) in entries.iter().enumerate() {
                        println!("  {}. {}", i + 1, query);
                    }
                }
            }
            _ => {
                // Run the search pipeline
                println!("\n🔄 Processing query: \"{}\"", query);
                println!("{}", "━".repeat(40));

                let query_string = query.to_string();

                match run_search_pipeline(query_string.clone(), &config).await {
                    Ok(output) => {
                        println!("{}", output);
                        history.add(query_string);
                    }
                    Err(e) => {
                        // Provide user-friendly error messages
                        if e.to_string().contains("rate limit") {
                            eprintln!("\n⏱️  Rate limit reached. Please wait 30 seconds and try again.");
                        } else if e.to_string().contains("authentication") {
                            eprintln!("\n🔑 Authentication error. Please check your API keys in .env file.");
                        } else if e.to_string().contains("Failed to send") {
                            eprintln!("\n🌐 Network error. Please check your internet connection.");
                        } else {
                            eprintln!("\n❌ Error: {}", e);
                        }
                        error!("Pipeline error: {}", e);
                    }
                }
            }
        }
    }

    Ok(())
}