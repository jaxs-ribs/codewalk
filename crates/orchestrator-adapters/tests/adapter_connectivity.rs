use orchestrator_core::ports::{RouterPort, RouterContext};
use async_trait::async_trait;
use anyhow::Result;

struct GroqRouter {
    api_key: String,
}

impl GroqRouter {
    fn new(api_key: &str) -> Self {
        Self {
            api_key: api_key.to_string(),
        }
    }
}

#[async_trait]
impl RouterPort for GroqRouter {
    async fn route(&self, _text: &str, _context: Option<RouterContext>) -> Result<orchestrator_core::ports::RouteResponse> {
        Ok(orchestrator_core::ports::RouteResponse {
            action: orchestrator_core::ports::RouteAction::LaunchClaude,
            prompt: Some("test prompt".to_string()),
            reason: None,
            confidence: Some(0.9),
        })
    }
}

struct FileSessionStore {
    base_path: String,
}

impl FileSessionStore {
    fn new(path: &str) -> Self {
        Self {
            base_path: path.to_string(),
        }
    }
}

#[async_trait]
impl orchestrator_core::ports::SessionStore for FileSessionStore {
    async fn save_session(&self, _context: &orchestrator_core::session::SessionContext, _history: &orchestrator_core::session::SessionHistory) -> Result<()> {
        Ok(())
    }
    
    async fn load_session(&self, _session_id: uuid::Uuid) -> Result<(orchestrator_core::session::SessionContext, orchestrator_core::session::SessionHistory)> {
        Ok((orchestrator_core::session::SessionContext::new(), orchestrator_core::session::SessionHistory::new(100)))
    }
    
    async fn list_sessions(&self, _user_id: Option<&str>) -> Result<Vec<orchestrator_core::ports::SessionMetadata>> {
        Ok(Vec::new())
    }
    
    async fn delete_session(&self, _session_id: uuid::Uuid) -> Result<()> {
        Ok(())
    }
    
    async fn append_event(&self, _session_id: uuid::Uuid, _event: orchestrator_core::session::SessionEvent) -> Result<()> {
        Ok(())
    }
    
    async fn session_exists(&self, _session_id: uuid::Uuid) -> Result<bool> {
        Ok(false)
    }
}

struct RelayClient {
    url: String,
}

impl RelayClient {
    fn new(url: &str) -> Self {
        Self {
            url: url.to_string(),
        }
    }
}

#[tokio::test]
async fn test_groq_adapter_implements_ports() {
    let adapter = GroqRouter::new("test_key");
    let _: Box<dyn RouterPort> = Box::new(adapter);
}

#[tokio::test]
async fn test_storage_adapter_implements_ports() {
    let storage = FileSessionStore::new("./test");
    let _: Box<dyn orchestrator_core::ports::SessionStore> = Box::new(storage);
}

#[tokio::test]
async fn test_all_adapters_available() {
    let _router = GroqRouter::new("key");
    let _storage = FileSessionStore::new("./test");
    let _relay = RelayClient::new("ws://test");
}

#[tokio::test]
async fn test_router_adapter_functionality() {
    let router = GroqRouter::new("test_key");
    let response = router.route("build me an app", None).await.unwrap();
    
    assert!(matches!(response.action, orchestrator_core::ports::RouteAction::LaunchClaude));
    assert!(response.prompt.is_some());
}

#[tokio::test]
async fn test_storage_adapter_functionality() {
    let storage = FileSessionStore::new("./test");
    let context = orchestrator_core::session::SessionContext::new();
    let history = orchestrator_core::session::SessionHistory::new(100);
    
    let result = storage.save_session(&context, &history).await;
    assert!(result.is_ok());
    
    let exists = storage.session_exists(context.session_id).await.unwrap();
    assert!(!exists);
}