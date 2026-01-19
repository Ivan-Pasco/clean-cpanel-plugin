//! Events Module
//!
//! Event emission and hook execution system.

mod hooks;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::sync::broadcast;

pub use hooks::HookExecutor;

/// Event types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum Event {
    InstanceStarted {
        username: String,
        port: u16,
        apps: Vec<String>,
    },
    InstanceStopped {
        username: String,
    },
    InstanceCrashed {
        username: String,
        exit_code: Option<i32>,
        reason: String,
    },
    AppDeployed {
        username: String,
        app_name: String,
    },
    AppRemoved {
        username: String,
        app_name: String,
    },
    ResourceLimitReached {
        username: String,
        resource: String,
        current: u64,
        limit: u64,
    },
    HealthCheckFailed {
        username: String,
        check_name: String,
        message: String,
    },
    ConfigReloaded,
    ServiceStarted,
    ServiceStopped,
}

/// Event with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEnvelope {
    pub event: Event,
    pub timestamp: DateTime<Utc>,
    pub metadata: HashMap<String, String>,
}

impl EventEnvelope {
    pub fn new(event: Event) -> Self {
        Self {
            event,
            timestamp: Utc::now(),
            metadata: HashMap::new(),
        }
    }

    pub fn with_metadata(mut self, key: &str, value: &str) -> Self {
        self.metadata.insert(key.to_string(), value.to_string());
        self
    }
}

/// Event emitter
pub struct EventEmitter {
    sender: broadcast::Sender<EventEnvelope>,
    hook_executor: HookExecutor,
}

impl EventEmitter {
    /// Create a new event emitter
    pub fn new(hooks_dir: std::path::PathBuf) -> Self {
        let (sender, _) = broadcast::channel(100);
        Self {
            sender,
            hook_executor: HookExecutor::new(hooks_dir),
        }
    }

    /// Emit an event
    pub async fn emit(&self, event: Event) {
        let envelope = EventEnvelope::new(event.clone());

        // Send to subscribers
        let _ = self.sender.send(envelope.clone());

        // Execute hooks
        self.hook_executor.execute(&event).await;

        tracing::debug!("Event emitted: {:?}", event);
    }

    /// Subscribe to events
    pub fn subscribe(&self) -> broadcast::Receiver<EventEnvelope> {
        self.sender.subscribe()
    }

    /// Get event name for logging
    pub fn event_name(event: &Event) -> &'static str {
        match event {
            Event::InstanceStarted { .. } => "instance.started",
            Event::InstanceStopped { .. } => "instance.stopped",
            Event::InstanceCrashed { .. } => "instance.crashed",
            Event::AppDeployed { .. } => "app.deployed",
            Event::AppRemoved { .. } => "app.removed",
            Event::ResourceLimitReached { .. } => "resource.limit_reached",
            Event::HealthCheckFailed { .. } => "health_check.failed",
            Event::ConfigReloaded => "config.reloaded",
            Event::ServiceStarted => "service.started",
            Event::ServiceStopped => "service.stopped",
        }
    }
}

impl Default for EventEmitter {
    fn default() -> Self {
        Self::new(std::path::PathBuf::from("/usr/local/cpanel/scripts/frame"))
    }
}
