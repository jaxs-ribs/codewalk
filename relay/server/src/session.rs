use anyhow::Result;
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::Utc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub token: String,
    pub created: i64,
}

impl Session {
    pub fn new(id: String, token: String) -> Self {
        Self {
            id,
            token,
            created: Utc::now().timestamp(),
        }
    }

    pub fn redis_key(&self) -> String {
        format!("sess:{}", self.id)
    }

    pub fn roles_key(&self) -> String {
        format!("sess:{}:roles", self.id)
    }

    pub fn channel_key(&self) -> String {
        format!("ch:{}", self.id)
    }

    pub async fn save(&self, redis: &ConnectionManager, ttl: u64) -> Result<()> {
        let mut conn = redis.clone();
        
        // Explicit return types avoid never-type fallback warnings
        conn.hset_multiple::<_, _, _, ()>(
            &self.redis_key(),
            &[
                ("token", &self.token),
                ("created", &self.created.to_string()),
            ],
        ).await?;
        
        conn.expire::<_, ()>(&self.redis_key(), ttl as i64).await?;
        conn.del::<_, ()>(&self.roles_key()).await?;
        
        Ok(())
    }

    pub async fn refresh(redis: &ConnectionManager, id: &str, ttl: u64) -> Result<()> {
        let mut conn = redis.clone();
        let key = format!("sess:{}", id);
        conn.expire::<_, ()>(&key, ttl as i64).await?;
        Ok(())
    }

    pub async fn load(id: &str, redis: &ConnectionManager) -> Result<Option<Self>> {
        let mut conn = redis.clone();
        let key = format!("sess:{}", id);
        
        let data: HashMap<String, String> = conn.hgetall(&key).await?;
        
        if data.is_empty() {
            return Ok(None);
        }
        
        Ok(Some(Self {
            id: id.to_string(),
            token: data.get("token").cloned().unwrap_or_default(),
            created: data.get("created")
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
        }))
    }
}

#[derive(Debug, Clone)]
pub struct SessionStore {
    sessions: HashMap<String, Session>,
}

impl SessionStore {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    pub fn add(&mut self, session: Session) {
        self.sessions.insert(session.id.clone(), session);
    }

    pub fn get(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id)
    }

    pub fn remove(&mut self, id: &str) -> Option<Session> {
        self.sessions.remove(id)
    }
}
