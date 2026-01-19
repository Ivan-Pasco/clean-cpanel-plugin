//! Health Monitoring Module
//!
//! Performs periodic health checks on Frame instances.

mod checks;

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::{interval, Duration};

pub use checks::{HealthCheck, HealthCheckResult};

use crate::instance::InstanceManager;

/// Health monitor service
pub struct HealthMonitor {
    /// Check interval in seconds
    interval_secs: u64,
    /// Instance manager reference
    instance_manager: Arc<InstanceManager>,
    /// Health status cache
    status_cache: Arc<RwLock<HashMap<String, HealthStatus>>>,
    /// Running flag
    running: Arc<RwLock<bool>>,
}

/// Health status for an instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub username: String,
    pub healthy: bool,
    pub checks: Vec<HealthCheckResult>,
    pub last_check: DateTime<Utc>,
    pub consecutive_failures: u32,
}

impl HealthMonitor {
    /// Create a new health monitor
    pub fn new(interval_secs: u64, instance_manager: Arc<InstanceManager>) -> Self {
        Self {
            interval_secs,
            instance_manager,
            status_cache: Arc::new(RwLock::new(HashMap::new())),
            running: Arc::new(RwLock::new(false)),
        }
    }

    /// Start the health monitor
    pub async fn start(&self) {
        let mut running = self.running.write().await;
        if *running {
            return;
        }
        *running = true;
        drop(running);

        let interval_secs = self.interval_secs;
        let instance_manager = Arc::clone(&self.instance_manager);
        let status_cache = Arc::clone(&self.status_cache);
        let running = Arc::clone(&self.running);

        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_secs(interval_secs));

            loop {
                ticker.tick().await;

                let is_running = *running.read().await;
                if !is_running {
                    break;
                }

                // Get all instances
                let instances = instance_manager.list().await;

                for instance in instances {
                    if instance.status != crate::instance::InstanceStatus::Running {
                        continue;
                    }

                    let username = instance.username.clone();
                    let mut checks = Vec::new();
                    let mut all_passed = true;

                    // Process check
                    if let Some(pid) = instance.pid {
                        let process_check = HealthCheck::process(pid);
                        let result = process_check.execute().await;
                        all_passed = all_passed && result.passed;
                        checks.push(result);
                    }

                    // Port check
                    let port_check = HealthCheck::port(instance.port);
                    let result = port_check.execute().await;
                    all_passed = all_passed && result.passed;
                    checks.push(result);

                    // HTTP check
                    let http_check = HealthCheck::http(instance.port, "/health");
                    let result = http_check.execute().await;
                    all_passed = all_passed && result.passed;
                    checks.push(result);

                    // Update status cache
                    let mut cache = status_cache.write().await;
                    let status = cache.entry(username.clone()).or_insert(HealthStatus {
                        username: username.clone(),
                        healthy: true,
                        checks: Vec::new(),
                        last_check: Utc::now(),
                        consecutive_failures: 0,
                    });

                    status.healthy = all_passed;
                    status.checks = checks;
                    status.last_check = Utc::now();

                    if all_passed {
                        status.consecutive_failures = 0;
                    } else {
                        status.consecutive_failures += 1;

                        // Auto-restart after 3 consecutive failures
                        if status.consecutive_failures >= 3 {
                            tracing::warn!(
                                "Instance for {} has failed {} consecutive health checks, restarting",
                                username,
                                status.consecutive_failures
                            );
                            if let Err(e) = instance_manager.restart(&username, instance.port).await {
                                tracing::error!("Failed to restart instance for {}: {}", username, e);
                            }
                            status.consecutive_failures = 0;
                        }
                    }
                }
            }
        });

        tracing::info!("Health monitor started (interval: {}s)", self.interval_secs);
    }

    /// Stop the health monitor
    pub async fn stop(&self) {
        let mut running = self.running.write().await;
        *running = false;
        tracing::info!("Health monitor stopped");
    }

    /// Get health status for a user
    pub async fn get_status(&self, username: &str) -> Option<HealthStatus> {
        let cache = self.status_cache.read().await;
        cache.get(username).cloned()
    }

    /// Get all health statuses
    pub async fn get_all_statuses(&self) -> Vec<HealthStatus> {
        let cache = self.status_cache.read().await;
        cache.values().cloned().collect()
    }

    /// Check if an instance is healthy
    pub async fn is_healthy(&self, username: &str) -> bool {
        let cache = self.status_cache.read().await;
        cache.get(username).map(|s| s.healthy).unwrap_or(false)
    }

    /// Run a manual health check
    pub async fn check_now(&self, username: &str) -> Result<HealthStatus> {
        let instance = self.instance_manager.status(username).await?;
        let mut checks = Vec::new();
        let mut all_passed = true;

        if let Some(pid) = instance.pid {
            let process_check = HealthCheck::process(pid);
            let result = process_check.execute().await;
            all_passed = all_passed && result.passed;
            checks.push(result);
        }

        let port_check = HealthCheck::port(instance.port);
        let result = port_check.execute().await;
        all_passed = all_passed && result.passed;
        checks.push(result);

        let http_check = HealthCheck::http(instance.port, "/health");
        let result = http_check.execute().await;
        all_passed = all_passed && result.passed;
        checks.push(result);

        let status = HealthStatus {
            username: username.to_string(),
            healthy: all_passed,
            checks,
            last_check: Utc::now(),
            consecutive_failures: 0,
        };

        // Update cache
        let mut cache = self.status_cache.write().await;
        cache.insert(username.to_string(), status.clone());

        Ok(status)
    }
}
