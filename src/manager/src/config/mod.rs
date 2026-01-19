//! Configuration Management
//!
//! Handles loading and parsing of Frame Manager configuration files.

mod parser;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub use parser::ConfigParser;

/// Main configuration structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub service: ServiceConfig,
    pub defaults: DefaultsConfig,
    pub logging: LoggingConfig,
    pub security: SecurityConfig,
    pub proxy: ProxyConfig,
}

/// Service configuration section
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceConfig {
    /// Enable Frame service globally
    pub enabled: bool,
    /// Start of port range for user instances
    pub port_range_start: u16,
    /// End of port range for user instances
    pub port_range_end: u16,
    /// Manager API port
    pub manager_port: u16,
    /// Auto-start instances on boot
    pub auto_start: bool,
    /// Health check interval in seconds
    pub health_check_interval: u64,
}

/// Default resource limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DefaultsConfig {
    /// Default memory limit in MB
    pub memory_limit: u64,
    /// Default CPU limit (percentage 0-100)
    pub cpu_limit: u8,
    /// Default max apps per user
    pub max_apps: u32,
    /// Default disk quota in MB
    pub disk_quota: u64,
}

/// Logging configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    /// Log level: trace, debug, info, warn, error
    pub level: String,
    /// Log retention in days
    pub retention_days: u32,
    /// Max log file size in MB
    pub max_file_size: u64,
}

/// Security configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// Allow filesystem access via Host Bridge
    pub allow_fs_access: bool,
    /// Allow system info access
    pub allow_sys_access: bool,
    /// Require HTTPS for external connections
    pub require_https: bool,
}

/// Proxy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    /// Proxy backend: apache or nginx
    pub backend: String,
    /// Proxy timeout in seconds
    pub timeout: u64,
    /// Enable WebSocket proxying
    pub websocket: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            service: ServiceConfig::default(),
            defaults: DefaultsConfig::default(),
            logging: LoggingConfig::default(),
            security: SecurityConfig::default(),
            proxy: ProxyConfig::default(),
        }
    }
}

impl Default for ServiceConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            port_range_start: 30001,
            port_range_end: 32000,
            manager_port: 30000,
            auto_start: true,
            health_check_interval: 30,
        }
    }
}

impl Default for DefaultsConfig {
    fn default() -> Self {
        Self {
            memory_limit: 512,
            cpu_limit: 25,
            max_apps: 5,
            disk_quota: 1024,
        }
    }
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: "info".to_string(),
            retention_days: 30,
            max_file_size: 100,
        }
    }
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            allow_fs_access: false,
            allow_sys_access: false,
            require_https: true,
        }
    }
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            backend: "apache".to_string(),
            timeout: 60,
            websocket: true,
        }
    }
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            tracing::warn!(
                "Configuration file not found: {}, using defaults",
                path.display()
            );
            return Ok(Self::default());
        }

        let parser = ConfigParser::new();
        parser
            .parse(path)
            .with_context(|| format!("Failed to parse config file: {}", path.display()))
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<()> {
        if self.service.port_range_start >= self.service.port_range_end {
            anyhow::bail!("port_range_start must be less than port_range_end");
        }

        if self.service.manager_port >= self.service.port_range_start
            && self.service.manager_port <= self.service.port_range_end
        {
            anyhow::bail!("manager_port must be outside the user port range");
        }

        if self.defaults.cpu_limit > 100 {
            anyhow::bail!("cpu_limit must be between 0 and 100");
        }

        Ok(())
    }
}

/// Package-specific configuration overrides
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageConfig {
    pub name: String,
    pub limits: PackageLimits,
    pub features: PackageFeatures,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageLimits {
    pub memory_limit: u64,
    pub cpu_limit: u8,
    pub max_apps: u32,
    pub disk_quota: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageFeatures {
    pub fs_access: bool,
    pub sys_access: bool,
    pub custom_domains: bool,
    pub ssl_support: bool,
}

impl PackageConfig {
    /// Load package configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        let parser = ConfigParser::new();
        parser.parse_package(path)
    }
}
