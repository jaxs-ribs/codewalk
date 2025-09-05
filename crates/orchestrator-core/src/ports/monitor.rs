use anyhow::Result;
use async_trait::async_trait;
use uuid::Uuid;

#[async_trait]
pub trait LogMonitor: Send + Sync {
    async fn log_event(&self, session_id: Uuid, level: LogLevel, message: String) -> Result<()>;
    
    async fn log_error(&self, session_id: Uuid, error: &anyhow::Error) -> Result<()>;
    
    async fn start_span(&self, session_id: Uuid, name: String) -> Result<SpanId>;
    
    async fn end_span(&self, span_id: SpanId) -> Result<()>;
    
    async fn record_metric(&self, name: String, value: MetricValue) -> Result<()>;
}

#[derive(Debug, Clone, Copy)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone)]
pub struct SpanId(pub Uuid);

#[derive(Debug, Clone)]
pub enum MetricValue {
    Count(u64),
    Gauge(f64),
    Histogram(f64),
    Duration(std::time::Duration),
}