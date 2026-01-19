//! Instance Management Module
//!
//! Manages per-user Frame instances including process lifecycle,
//! resource limits, and monitoring.

mod process;
mod resource;

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;

pub use process::ProcessManager;
pub use resource::ResourceLimits;

/// Instance manager
pub struct InstanceManager {
    /// Base directory for instance data
    instances_dir: PathBuf,
    /// Frame server binary path
    frame_server_path: PathBuf,
    /// Process manager
    process_manager: ProcessManager,
    /// Active instances
    instances: Arc<RwLock<HashMap<String, Instance>>>,
    /// Default resource limits
    default_limits: ResourceLimits,
}

/// Represents a user's Frame instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Instance {
    /// Username
    pub username: String,
    /// Allocated port
    pub port: u16,
    /// Current status
    pub status: InstanceStatus,
    /// Process ID (if running)
    pub pid: Option<u32>,
    /// Memory usage in bytes
    pub memory_usage: u64,
    /// CPU usage percentage
    pub cpu_usage: f32,
    /// Number of deployed apps
    pub app_count: u32,
    /// Resource limits
    pub limits: ResourceLimits,
    /// When the instance was started
    pub started_at: Option<DateTime<Utc>>,
    /// Last health check
    pub last_health_check: Option<DateTime<Utc>>,
}

/// Instance status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InstanceStatus {
    Running,
    Stopped,
    Starting,
    Stopping,
    Failed,
    Unknown,
}

impl std::fmt::Display for InstanceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            InstanceStatus::Running => write!(f, "running"),
            InstanceStatus::Stopped => write!(f, "stopped"),
            InstanceStatus::Starting => write!(f, "starting"),
            InstanceStatus::Stopping => write!(f, "stopping"),
            InstanceStatus::Failed => write!(f, "failed"),
            InstanceStatus::Unknown => write!(f, "unknown"),
        }
    }
}

/// Instance configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstanceConfig {
    pub auto_start: bool,
    pub memory_limit: u64,
    pub max_apps: u32,
    pub env_vars: HashMap<String, String>,
}

impl Default for InstanceConfig {
    fn default() -> Self {
        Self {
            auto_start: true,
            memory_limit: 512,
            max_apps: 5,
            env_vars: HashMap::new(),
        }
    }
}

impl InstanceManager {
    /// Create a new instance manager
    pub fn new(
        instances_dir: PathBuf,
        frame_server_path: PathBuf,
        default_limits: ResourceLimits,
    ) -> Self {
        Self {
            instances_dir,
            frame_server_path,
            process_manager: ProcessManager::new(),
            instances: Arc::new(RwLock::new(HashMap::new())),
            default_limits,
        }
    }

    /// Initialize the instance manager
    pub async fn init(&self) -> Result<()> {
        // Scan existing instance directories
        if self.instances_dir.exists() {
            let mut entries = tokio::fs::read_dir(&self.instances_dir).await?;
            while let Some(entry) = entries.next_entry().await? {
                if entry.file_type().await?.is_dir() {
                    if let Some(username) = entry.file_name().to_str() {
                        self.load_instance(username).await?;
                    }
                }
            }
        }
        Ok(())
    }

    /// Load an existing instance
    async fn load_instance(&self, username: &str) -> Result<()> {
        let instance_dir = self.instances_dir.join(username);
        let config_path = instance_dir.join("config.json");

        let config = if config_path.exists() {
            let content = tokio::fs::read_to_string(&config_path).await?;
            serde_json::from_str(&content)?
        } else {
            InstanceConfig::default()
        };

        let instance = Instance {
            username: username.to_string(),
            port: 0, // Will be set by port allocator
            status: InstanceStatus::Stopped,
            pid: None,
            memory_usage: 0,
            cpu_usage: 0.0,
            app_count: self.count_apps(username).await?,
            limits: ResourceLimits {
                memory_mb: config.memory_limit,
                cpu_percent: self.default_limits.cpu_percent,
                max_connections: self.default_limits.max_connections,
                max_apps: config.max_apps,
                disk_quota_mb: self.default_limits.disk_quota_mb,
            },
            started_at: None,
            last_health_check: None,
        };

        let mut instances = self.instances.write().await;
        instances.insert(username.to_string(), instance);

        Ok(())
    }

    /// Count apps for a user
    async fn count_apps(&self, username: &str) -> Result<u32> {
        let apps_dir = self.instances_dir.join(username).join("apps");
        if !apps_dir.exists() {
            return Ok(0);
        }

        let mut count = 0;
        let mut entries = tokio::fs::read_dir(&apps_dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            if entry.file_type().await?.is_dir() {
                count += 1;
            }
        }
        Ok(count)
    }

    /// Start an instance
    pub async fn start(&self, username: &str, port: u16) -> Result<()> {
        let mut instances = self.instances.write().await;

        let instance = instances
            .get_mut(username)
            .ok_or_else(|| anyhow::anyhow!("Instance not found for user: {}", username))?;

        if instance.status == InstanceStatus::Running {
            return Ok(());
        }

        instance.status = InstanceStatus::Starting;
        instance.port = port;

        // Start the process
        let pid = self
            .process_manager
            .spawn(
                username,
                &self.frame_server_path,
                port,
                &self.instances_dir.join(username),
                &instance.limits,
            )
            .await?;

        instance.pid = Some(pid);
        instance.status = InstanceStatus::Running;
        instance.started_at = Some(Utc::now());

        tracing::info!("Started instance for user {} on port {} (PID: {})", username, port, pid);

        Ok(())
    }

    /// Stop an instance
    pub async fn stop(&self, username: &str) -> Result<()> {
        let mut instances = self.instances.write().await;

        let instance = instances
            .get_mut(username)
            .ok_or_else(|| anyhow::anyhow!("Instance not found for user: {}", username))?;

        if instance.status == InstanceStatus::Stopped {
            return Ok(());
        }

        instance.status = InstanceStatus::Stopping;

        if let Some(pid) = instance.pid {
            self.process_manager.stop(pid).await?;
        }

        instance.pid = None;
        instance.status = InstanceStatus::Stopped;
        instance.started_at = None;

        tracing::info!("Stopped instance for user {}", username);

        Ok(())
    }

    /// Restart an instance
    pub async fn restart(&self, username: &str, port: u16) -> Result<()> {
        self.stop(username).await?;
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        self.start(username, port).await?;
        Ok(())
    }

    /// Get instance status
    pub async fn status(&self, username: &str) -> Result<Instance> {
        let instances = self.instances.read().await;
        instances
            .get(username)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Instance not found for user: {}", username))
    }

    /// List all instances
    pub async fn list(&self) -> Vec<Instance> {
        let instances = self.instances.read().await;
        instances.values().cloned().collect()
    }

    /// Create a new instance for a user
    pub async fn create(&self, username: &str, limits: Option<ResourceLimits>) -> Result<()> {
        let instance_dir = self.instances_dir.join(username);

        // Create directory structure
        tokio::fs::create_dir_all(instance_dir.join("apps")).await?;
        tokio::fs::create_dir_all(instance_dir.join("data")).await?;
        tokio::fs::create_dir_all(instance_dir.join("logs")).await?;

        // Create default config
        let config = InstanceConfig::default();
        let config_json = serde_json::to_string_pretty(&config)?;
        tokio::fs::write(instance_dir.join("config.json"), config_json).await?;

        // Set ownership (requires root)
        #[cfg(unix)]
        {
            use std::os::unix::fs::chown;
            if let Ok(Some(user)) = nix::unistd::User::from_name(username) {
                let uid = user.uid.as_raw();
                let gid = user.gid.as_raw();

                fn chown_recursive(path: &Path, uid: u32, gid: u32) -> std::io::Result<()> {
                    chown(path, Some(uid), Some(gid))?;
                    if path.is_dir() {
                        for entry in std::fs::read_dir(path)? {
                            chown_recursive(&entry?.path(), uid, gid)?;
                        }
                    }
                    Ok(())
                }

                let _ = chown_recursive(&instance_dir, uid, gid);
            }
        }

        let instance = Instance {
            username: username.to_string(),
            port: 0,
            status: InstanceStatus::Stopped,
            pid: None,
            memory_usage: 0,
            cpu_usage: 0.0,
            app_count: 0,
            limits: limits.unwrap_or_else(|| self.default_limits.clone()),
            started_at: None,
            last_health_check: None,
        };

        let mut instances = self.instances.write().await;
        instances.insert(username.to_string(), instance);

        tracing::info!("Created instance for user {}", username);

        Ok(())
    }

    /// Remove an instance
    pub async fn remove(&self, username: &str) -> Result<()> {
        // Stop if running
        let _ = self.stop(username).await;

        // Remove from tracked instances
        let mut instances = self.instances.write().await;
        instances.remove(username);

        // Remove directory
        let instance_dir = self.instances_dir.join(username);
        if instance_dir.exists() {
            tokio::fs::remove_dir_all(&instance_dir).await?;
        }

        tracing::info!("Removed instance for user {}", username);

        Ok(())
    }

    /// Update instance resource usage
    pub async fn update_usage(&self, username: &str) -> Result<()> {
        let mut instances = self.instances.write().await;

        if let Some(instance) = instances.get_mut(username) {
            if let Some(pid) = instance.pid {
                let (memory, cpu) = self.process_manager.get_resource_usage(pid)?;
                instance.memory_usage = memory;
                instance.cpu_usage = cpu;
                instance.last_health_check = Some(Utc::now());
            }
        }

        Ok(())
    }

    /// Check if instance is healthy
    pub async fn is_healthy(&self, username: &str) -> bool {
        let instances = self.instances.read().await;

        if let Some(instance) = instances.get(username) {
            if instance.status != InstanceStatus::Running {
                return false;
            }

            if let Some(pid) = instance.pid {
                return self.process_manager.is_running(pid);
            }
        }

        false
    }

    /// Get running instance count
    pub async fn running_count(&self) -> usize {
        let instances = self.instances.read().await;
        instances
            .values()
            .filter(|i| i.status == InstanceStatus::Running)
            .count()
    }

    /// Get total instance count
    pub async fn total_count(&self) -> usize {
        let instances = self.instances.read().await;
        instances.len()
    }
}
