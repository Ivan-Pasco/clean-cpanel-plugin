//! Frame Manager - Main Orchestration Module
//!
//! Coordinates all Frame manager components.

use anyhow::Result;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::api::handlers::{InstanceStatusResponse, ServiceStatus, SettingsUpdate, PackageUpdate};
use crate::api::ApiServer;
use crate::config::{Config, PackageConfig};
use crate::events::{Event, EventEmitter};
use crate::health::HealthMonitor;
use crate::instance::{Instance, InstanceManager, ResourceLimits};
use crate::metrics::MetricsCollector;
use crate::port::PortAllocator;

/// Main Frame Manager
pub struct FrameManager {
    /// Configuration
    config: Arc<RwLock<Config>>,
    /// Configuration file path
    config_path: PathBuf,
    /// Instance manager
    instance_manager: Arc<InstanceManager>,
    /// Port allocator
    port_allocator: Arc<PortAllocator>,
    /// Health monitor
    health_monitor: Arc<HealthMonitor>,
    /// Metrics collector
    metrics: Arc<RwLock<MetricsCollector>>,
    /// Event emitter
    events: Arc<EventEmitter>,
    /// API server
    api_server: Option<Arc<ApiServer>>,
    /// Running state
    running: Arc<RwLock<bool>>,
}

impl FrameManager {
    /// Create a new Frame manager
    pub async fn new(config: Config) -> Result<Arc<Self>> {
        let config_path = PathBuf::from("/etc/frame/frame.conf");
        let instances_dir = PathBuf::from("/var/frame/instances");
        let ports_registry = PathBuf::from("/var/frame/manager/ports.json");
        let frame_server_path = PathBuf::from("/usr/local/cpanel/3rdparty/bin/frame-server");

        // Create default resource limits from config
        let default_limits = ResourceLimits::from_defaults(
            config.defaults.memory_limit,
            config.defaults.cpu_limit,
            config.defaults.max_apps,
            config.defaults.disk_quota,
        );

        // Initialize components
        let port_allocator = Arc::new(PortAllocator::new(
            config.service.port_range_start,
            config.service.port_range_end,
            &ports_registry,
        )?);

        let instance_manager = Arc::new(InstanceManager::new(
            instances_dir,
            frame_server_path,
            default_limits,
        ));

        let health_monitor = Arc::new(HealthMonitor::new(
            config.service.health_check_interval,
            Arc::clone(&instance_manager),
        ));

        let metrics = Arc::new(RwLock::new(MetricsCollector::default()));
        let events = Arc::new(EventEmitter::default());

        let manager = Arc::new(Self {
            config: Arc::new(RwLock::new(config)),
            config_path,
            instance_manager,
            port_allocator,
            health_monitor,
            metrics,
            events,
            api_server: None,
            running: Arc::new(RwLock::new(false)),
        });

        Ok(manager)
    }

    /// Run the Frame manager (main loop)
    pub async fn run(self: &Arc<Self>) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            anyhow::bail!("Manager is already running");
        }
        *running = true;
        drop(running);

        tracing::info!("Starting Frame Manager...");

        // Initialize instance manager
        self.instance_manager.init().await?;

        // Start health monitor
        self.health_monitor.start().await;

        // Emit service started event
        self.events.emit(Event::ServiceStarted).await;

        // Auto-start instances if configured
        let config = self.config.read().await;
        if config.service.auto_start {
            drop(config);
            self.auto_start_instances().await?;
        }

        // Start API server
        let config = self.config.read().await;
        let api_port = config.service.manager_port;
        drop(config);

        tracing::info!("Frame Manager is running on port {}", api_port);

        // Create and run API server (this blocks)
        let api_server = ApiServer::new(api_port, Arc::clone(&self.clone()));
        api_server.start().await?;

        Ok(())
    }

    /// Clone the Arc for passing to API server
    fn clone(&self) -> Arc<Self> {
        Arc::new(Self {
            config: Arc::clone(&self.config),
            config_path: self.config_path.clone(),
            instance_manager: Arc::clone(&self.instance_manager),
            port_allocator: Arc::clone(&self.port_allocator),
            health_monitor: Arc::clone(&self.health_monitor),
            metrics: Arc::clone(&self.metrics),
            events: Arc::clone(&self.events),
            api_server: self.api_server.clone(),
            running: Arc::clone(&self.running),
        })
    }

    /// Stop the Frame manager
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }
        *running = false;
        drop(running);

        tracing::info!("Stopping Frame Manager...");

        // Stop health monitor
        self.health_monitor.stop().await;

        // Stop all instances
        let instances = self.instance_manager.list().await;
        for instance in instances {
            let _ = self.instance_manager.stop(&instance.username).await;
        }

        // Stop API server
        if let Some(api_server) = &self.api_server {
            api_server.stop().await;
        }

        // Emit service stopped event
        self.events.emit(Event::ServiceStopped).await;

        tracing::info!("Frame Manager stopped");

        Ok(())
    }

    /// Auto-start instances with auto_start enabled
    async fn auto_start_instances(&self) -> Result<()> {
        let instances = self.instance_manager.list().await;

        for instance in instances {
            // Check if instance config has auto_start
            let config_path = PathBuf::from("/var/frame/instances")
                .join(&instance.username)
                .join("config.json");

            if config_path.exists() {
                let content = tokio::fs::read_to_string(&config_path).await?;
                let config: serde_json::Value = serde_json::from_str(&content)?;

                if config.get("auto_start").and_then(|v| v.as_bool()).unwrap_or(true) {
                    if let Err(e) = self.start_instance(&instance.username).await {
                        tracing::error!(
                            "Failed to auto-start instance for {}: {}",
                            instance.username,
                            e
                        );
                    }
                }
            }
        }

        Ok(())
    }

    /// Get service status
    pub async fn status(&self) -> Result<ServiceStatus> {
        let config = self.config.read().await;
        let running_count = self.instance_manager.running_count().await;
        let total_count = self.instance_manager.total_count().await;

        // Calculate total memory usage
        let instances = self.instance_manager.list().await;
        let total_memory: u64 = instances.iter().map(|i| i.memory_usage).sum();

        Ok(ServiceStatus {
            service_status: if *self.running.read().await {
                "running".to_string()
            } else {
                "stopped".to_string()
            },
            instances_running: running_count,
            instances_total: total_count,
            memory_usage_mb: total_memory / 1024 / 1024,
            port_range: format!(
                "{}-{}",
                config.service.port_range_start, config.service.port_range_end
            ),
        })
    }

    /// Start a user instance
    pub async fn start_instance(&self, username: &str) -> Result<()> {
        // Allocate port
        let port = self.port_allocator.allocate(username).await?;

        // Start instance
        self.instance_manager.start(username, port).await?;

        // Emit event
        let apps = self.get_user_apps(username).await?;
        self.events
            .emit(Event::InstanceStarted {
                username: username.to_string(),
                port,
                apps,
            })
            .await;

        // Update metrics
        self.update_metrics().await;

        Ok(())
    }

    /// Stop a user instance
    pub async fn stop_instance(&self, username: &str) -> Result<()> {
        self.instance_manager.stop(username).await?;

        // Emit event
        self.events
            .emit(Event::InstanceStopped {
                username: username.to_string(),
            })
            .await;

        // Update metrics
        self.update_metrics().await;

        Ok(())
    }

    /// Restart a user instance
    pub async fn restart_instance(&self, username: &str) -> Result<()> {
        let port = self
            .port_allocator
            .get_port(username)
            .await
            .ok_or_else(|| anyhow::anyhow!("No port allocated for user: {}", username))?;

        self.instance_manager.restart(username, port).await?;

        // Update metrics
        self.update_metrics().await;

        Ok(())
    }

    /// Restart all instances
    pub async fn restart_all(&self) -> Result<()> {
        let instances = self.instance_manager.list().await;

        for instance in instances {
            if instance.status == crate::instance::InstanceStatus::Running {
                let _ = self.restart_instance(&instance.username).await;
            }
        }

        Ok(())
    }

    /// Get instance status
    pub async fn instance_status(&self, username: &str) -> Result<InstanceStatusResponse> {
        let instance = self.instance_manager.status(username).await?;

        Ok(InstanceStatusResponse {
            username: instance.username,
            status: instance.status.to_string(),
            port: instance.port,
            memory_usage_mb: instance.memory_usage / 1024 / 1024,
            cpu_usage: instance.cpu_usage,
            app_count: instance.app_count,
        })
    }

    /// List all instances
    pub async fn list_instances(&self) -> Result<Vec<InstanceStatusResponse>> {
        let instances = self.instance_manager.list().await;

        Ok(instances
            .into_iter()
            .map(|i| InstanceStatusResponse {
                username: i.username,
                status: i.status.to_string(),
                port: i.port,
                memory_usage_mb: i.memory_usage / 1024 / 1024,
                cpu_usage: i.cpu_usage,
                app_count: i.app_count,
            })
            .collect())
    }

    /// Allocate a port for a user
    pub async fn allocate_port(&self, username: &str) -> Result<u16> {
        self.port_allocator.allocate(username).await
    }

    /// Release a user's port
    pub async fn release_port(&self, username: &str) -> Result<()> {
        self.port_allocator.release(username).await
    }

    /// List port allocations
    pub async fn list_ports(&self) -> Result<serde_json::Value> {
        let allocations = self.port_allocator.list_allocations().await;
        let stats = self.port_allocator.stats().await;

        Ok(serde_json::json!({
            "allocations": allocations,
            "stats": stats
        }))
    }

    /// Get logs for a user
    pub async fn get_logs(&self, username: &str, lines: usize) -> Result<Vec<String>> {
        let log_path = PathBuf::from("/var/frame/instances")
            .join(username)
            .join("logs")
            .join("frame.log");

        if !log_path.exists() {
            return Ok(Vec::new());
        }

        let content = tokio::fs::read_to_string(&log_path).await?;
        let all_lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();

        // Return last N lines
        let start = if all_lines.len() > lines {
            all_lines.len() - lines
        } else {
            0
        };

        Ok(all_lines[start..].to_vec())
    }

    /// Get user's apps
    async fn get_user_apps(&self, username: &str) -> Result<Vec<String>> {
        let apps_dir = PathBuf::from("/var/frame/instances")
            .join(username)
            .join("apps");

        if !apps_dir.exists() {
            return Ok(Vec::new());
        }

        let mut apps = Vec::new();
        let mut entries = tokio::fs::read_dir(&apps_dir).await?;

        while let Some(entry) = entries.next_entry().await? {
            if entry.file_type().await?.is_dir() {
                if let Some(name) = entry.file_name().to_str() {
                    apps.push(name.to_string());
                }
            }
        }

        Ok(apps)
    }

    /// Get settings
    pub async fn get_settings(&self) -> Result<serde_json::Value> {
        let config = self.config.read().await;
        Ok(serde_json::to_value(&*config)?)
    }

    /// Update settings
    pub async fn update_settings(&self, update: SettingsUpdate) -> Result<()> {
        let mut config = self.config.write().await;

        if let Some(enabled) = update.enabled {
            config.service.enabled = enabled;
        }
        if let Some(auto_start) = update.auto_start {
            config.service.auto_start = auto_start;
        }
        if let Some(interval) = update.health_check_interval {
            config.service.health_check_interval = interval;
        }

        // Save to file
        let content = format!(
            "[service]\nenabled = {}\nauto_start = {}\nhealth_check_interval = {}\n",
            config.service.enabled,
            config.service.auto_start,
            config.service.health_check_interval
        );

        tokio::fs::write(&self.config_path, content).await?;

        // Emit event
        drop(config);
        self.events.emit(Event::ConfigReloaded).await;

        Ok(())
    }

    /// List packages
    pub async fn list_packages(&self) -> Result<Vec<serde_json::Value>> {
        let packages_dir = PathBuf::from("/etc/frame/packages");

        if !packages_dir.exists() {
            return Ok(Vec::new());
        }

        let mut packages = Vec::new();
        let mut entries = tokio::fs::read_dir(&packages_dir).await?;

        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("conf") {
                if let Ok(pkg) = PackageConfig::load(&path) {
                    packages.push(serde_json::to_value(&pkg)?);
                }
            }
        }

        Ok(packages)
    }

    /// Update package
    pub async fn update_package(&self, name: &str, update: PackageUpdate) -> Result<()> {
        let package_path = PathBuf::from("/etc/frame/packages").join(format!("{}.conf", name));

        let mut content = String::new();
        content.push_str("[limits]\n");

        if let Some(memory) = update.memory_limit {
            content.push_str(&format!("memory_limit = {}\n", memory));
        }
        if let Some(cpu) = update.cpu_limit {
            content.push_str(&format!("cpu_limit = {}\n", cpu));
        }
        if let Some(apps) = update.max_apps {
            content.push_str(&format!("max_apps = {}\n", apps));
        }
        if let Some(disk) = update.disk_quota {
            content.push_str(&format!("disk_quota = {}\n", disk));
        }

        tokio::fs::write(&package_path, content).await?;

        Ok(())
    }

    /// Reload configuration
    pub async fn reload_config(&self) -> Result<()> {
        let new_config = Config::load(&self.config_path)?;

        let mut config = self.config.write().await;
        *config = new_config;
        drop(config);

        self.events.emit(Event::ConfigReloaded).await;

        tracing::info!("Configuration reloaded");

        Ok(())
    }

    /// Get statistics
    pub async fn stats(&self, stat_type: Option<&str>) -> Result<serde_json::Value> {
        match stat_type {
            Some("memory") => {
                let instances = self.instance_manager.list().await;
                let memory_stats: Vec<serde_json::Value> = instances
                    .iter()
                    .map(|i| {
                        serde_json::json!({
                            "username": i.username,
                            "memory_mb": i.memory_usage / 1024 / 1024,
                            "limit_mb": i.limits.memory_mb
                        })
                    })
                    .collect();
                Ok(serde_json::json!({"memory": memory_stats}))
            }
            Some("cpu") => {
                let instances = self.instance_manager.list().await;
                let cpu_stats: Vec<serde_json::Value> = instances
                    .iter()
                    .map(|i| {
                        serde_json::json!({
                            "username": i.username,
                            "cpu_percent": i.cpu_usage,
                            "limit_percent": i.limits.cpu_percent
                        })
                    })
                    .collect();
                Ok(serde_json::json!({"cpu": cpu_stats}))
            }
            Some("instances") | None => {
                let running = self.instance_manager.running_count().await;
                let total = self.instance_manager.total_count().await;
                let port_stats = self.port_allocator.stats().await;

                Ok(serde_json::json!({
                    "instances": {
                        "running": running,
                        "stopped": total - running,
                        "total": total
                    },
                    "ports": port_stats
                }))
            }
            _ => anyhow::bail!("Unknown stat type: {}", stat_type.unwrap_or("none")),
        }
    }

    /// Get Prometheus metrics
    pub async fn get_metrics(&self) -> Result<String> {
        self.update_metrics().await;

        let metrics = self.metrics.read().await;
        Ok(metrics.export_prometheus())
    }

    /// Update metrics
    async fn update_metrics(&self) {
        let mut metrics = self.metrics.write().await;

        let instances = self.instance_manager.list().await;
        let running = instances
            .iter()
            .filter(|i| i.status == crate::instance::InstanceStatus::Running)
            .count();
        let stopped = instances.len() - running;

        metrics.set_gauge(
            "frame_instances_total",
            instances.len() as f64,
            HashMap::new(),
        );
        metrics.set_gauge("frame_instances_running", running as f64, HashMap::new());
        metrics.set_gauge("frame_instances_stopped", stopped as f64, HashMap::new());

        // Per-instance metrics
        for instance in &instances {
            let mut labels = HashMap::new();
            labels.insert("user".to_string(), instance.username.clone());

            metrics.set_gauge(
                "frame_memory_usage_bytes",
                instance.memory_usage as f64,
                labels.clone(),
            );
            metrics.set_gauge(
                "frame_cpu_usage_percent",
                instance.cpu_usage as f64,
                labels.clone(),
            );
            metrics.set_gauge("frame_apps_total", instance.app_count as f64, labels);
        }

        // Port metrics
        let port_stats = self.port_allocator.stats().await;
        metrics.set_gauge(
            "frame_ports_allocated",
            port_stats.allocated as f64,
            HashMap::new(),
        );
        metrics.set_gauge(
            "frame_ports_available",
            port_stats.available as f64,
            HashMap::new(),
        );
    }
}
