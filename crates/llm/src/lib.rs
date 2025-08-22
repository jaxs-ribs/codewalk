use anyhow::{Context, Result, anyhow};
use reqwest::Client as Http;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Clone, Debug)]
pub enum Provider {
    Groq, // add more later
}

#[derive(Clone, Debug)]
pub struct Client {
    http: Http,
    provider: Provider,
    api_key: String,
    model: String,
    base_url: String, // provider-specific defaulted
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role { System, User, Assistant }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: Role,
    pub content: String,
}

#[derive(Clone, Debug, Default)]
pub struct ChatOptions {
    pub temperature: Option<f32>,
    /// If true, request JSON-only output (`json_object`) when provider supports it.
    pub json_object: bool,
}

impl Client {
    pub fn new(provider: Provider, api_key: String, model: String) -> Result<Self> {
        let base_url = match provider {
            Provider::Groq => "https://api.groq.com/openai/v1".to_string(),
        };
        Ok(Self {
            http: Http::builder().pool_max_idle_per_host(8).build()?,
            provider, api_key, model, base_url,
        })
    }

    /// Convenience: pick up GROQ_API_KEY from env for Groq.
    pub fn from_env_groq(model: &str) -> Result<Self> {
        let key = std::env::var("GROQ_API_KEY").context("GROQ_API_KEY not set")?;
        Self::new(Provider::Groq, key, model.to_string())
    }

    pub async fn chat(&self, messages: &[ChatMessage], opts: ChatOptions) -> Result<String> {
        match self.provider {
            Provider::Groq => self.chat_groq(messages, opts).await,
        }
    }

    async fn chat_groq(&self, messages: &[ChatMessage], opts: ChatOptions) -> Result<String> {
        // OpenAI-compatible Chat Completions
        let url = format!("{}/chat/completions", self.base_url);

        // Convert Role enum to strings groq expects
        let msgs: Vec<Value> = messages.iter().map(|m| {
            let role = match m.role { Role::System=>"system", Role::User=>"user", Role::Assistant=>"assistant" };
            json!({ "role": role, "content": m.content })
        }).collect();

        let mut body = json!({
            "model": self.model,
            "messages": msgs,
            "temperature": opts.temperature.unwrap_or(0.0)
        });
        if opts.json_object {
            body.as_object_mut().unwrap().insert(
                "response_format".into(),
                json!({ "type": "json_object" })
            );
        }

        let resp = self.http.post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send().await
            .context("request failed")?;

        if !resp.status().is_success() {
            return Err(anyhow!("groq {}: {}", resp.status(), resp.text().await.unwrap_or_default()));
        }

        let v: Value = resp.json().await.context("invalid json")?;
        let content = v.pointer("/choices/0/message/content")
            .and_then(|x| x.as_str())
            .ok_or_else(|| anyhow!("missing choices[0].message.content"))?;
        Ok(content.to_string())
    }

    /// Simple helper for one-shot prompts.
    pub async fn simple(&self, prompt: &str) -> Result<String> {
        let msgs = vec![ChatMessage{ role: Role::User, content: prompt.to_string() }];
        self.chat(&msgs, ChatOptions::default()).await
    }
}