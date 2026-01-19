//! INI Configuration Parser

use anyhow::Result;
use configparser::ini::Ini;
use std::path::Path;

use super::{
    Config, DefaultsConfig, LoggingConfig, PackageConfig, PackageFeatures, PackageLimits,
    ProxyConfig, SecurityConfig, ServiceConfig,
};

/// Configuration file parser
pub struct ConfigParser {
    _ini: Ini,
}

impl ConfigParser {
    pub fn new() -> Self {
        Self { _ini: Ini::new() }
    }

    /// Parse main configuration file
    pub fn parse(&self, path: &Path) -> Result<Config> {
        let mut ini = Ini::new();
        ini.load(path)
            .map_err(|e| anyhow::anyhow!("Failed to load config: {}", e))?;

        let service = self.parse_service_section(&ini)?;
        let defaults = self.parse_defaults_section(&ini)?;
        let logging = self.parse_logging_section(&ini)?;
        let security = self.parse_security_section(&ini)?;
        let proxy = self.parse_proxy_section(&ini)?;

        let config = Config {
            service,
            defaults,
            logging,
            security,
            proxy,
        };

        config.validate()?;
        Ok(config)
    }

    fn parse_service_section(&self, ini: &Ini) -> Result<ServiceConfig> {
        let mut config = ServiceConfig::default();

        if let Ok(Some(val)) = ini.getbool("service", "enabled") {
            config.enabled = val;
        }
        if let Ok(Some(val)) = ini.getuint("service", "port_range_start") {
            config.port_range_start = val as u16;
        }
        if let Ok(Some(val)) = ini.getuint("service", "port_range_end") {
            config.port_range_end = val as u16;
        }
        if let Ok(Some(val)) = ini.getuint("service", "manager_port") {
            config.manager_port = val as u16;
        }
        if let Ok(Some(val)) = ini.getbool("service", "auto_start") {
            config.auto_start = val;
        }
        if let Ok(Some(val)) = ini.getuint("service", "health_check_interval") {
            config.health_check_interval = val;
        }

        Ok(config)
    }

    fn parse_defaults_section(&self, ini: &Ini) -> Result<DefaultsConfig> {
        let mut config = DefaultsConfig::default();

        if let Ok(Some(val)) = ini.getuint("defaults", "memory_limit") {
            config.memory_limit = val;
        }
        if let Ok(Some(val)) = ini.getuint("defaults", "cpu_limit") {
            config.cpu_limit = val as u8;
        }
        if let Ok(Some(val)) = ini.getuint("defaults", "max_apps") {
            config.max_apps = val as u32;
        }
        if let Ok(Some(val)) = ini.getuint("defaults", "disk_quota") {
            config.disk_quota = val;
        }

        Ok(config)
    }

    fn parse_logging_section(&self, ini: &Ini) -> Result<LoggingConfig> {
        let mut config = LoggingConfig::default();

        if let Some(val) = ini.get("logging", "level") {
            config.level = val;
        }
        if let Ok(Some(val)) = ini.getuint("logging", "retention_days") {
            config.retention_days = val as u32;
        }
        if let Ok(Some(val)) = ini.getuint("logging", "max_file_size") {
            config.max_file_size = val;
        }

        Ok(config)
    }

    fn parse_security_section(&self, ini: &Ini) -> Result<SecurityConfig> {
        let mut config = SecurityConfig::default();

        if let Ok(Some(val)) = ini.getbool("security", "allow_fs_access") {
            config.allow_fs_access = val;
        }
        if let Ok(Some(val)) = ini.getbool("security", "allow_sys_access") {
            config.allow_sys_access = val;
        }
        if let Ok(Some(val)) = ini.getbool("security", "require_https") {
            config.require_https = val;
        }

        Ok(config)
    }

    fn parse_proxy_section(&self, ini: &Ini) -> Result<ProxyConfig> {
        let mut config = ProxyConfig::default();

        if let Some(val) = ini.get("proxy", "backend") {
            config.backend = val;
        }
        if let Ok(Some(val)) = ini.getuint("proxy", "timeout") {
            config.timeout = val;
        }
        if let Ok(Some(val)) = ini.getbool("proxy", "websocket") {
            config.websocket = val;
        }

        Ok(config)
    }

    /// Parse package-specific configuration
    pub fn parse_package(&self, path: &Path) -> Result<PackageConfig> {
        let mut ini = Ini::new();
        ini.load(path)
            .map_err(|e| anyhow::anyhow!("Failed to load package config: {}", e))?;

        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string();

        let limits = self.parse_package_limits(&ini);
        let features = self.parse_package_features(&ini);

        Ok(PackageConfig {
            name,
            limits,
            features,
        })
    }

    fn parse_package_limits(&self, ini: &Ini) -> PackageLimits {
        PackageLimits {
            memory_limit: ini.getuint("limits", "memory_limit").ok().flatten().unwrap_or(512),
            cpu_limit: ini.getuint("limits", "cpu_limit").ok().flatten().unwrap_or(25) as u8,
            max_apps: ini.getuint("limits", "max_apps").ok().flatten().unwrap_or(5) as u32,
            disk_quota: ini.getuint("limits", "disk_quota").ok().flatten().unwrap_or(1024),
        }
    }

    fn parse_package_features(&self, ini: &Ini) -> PackageFeatures {
        PackageFeatures {
            fs_access: ini.getbool("features", "fs_access").ok().flatten().unwrap_or(false),
            sys_access: ini.getbool("features", "sys_access").ok().flatten().unwrap_or(false),
            custom_domains: ini.getbool("features", "custom_domains").ok().flatten().unwrap_or(true),
            ssl_support: ini.getbool("features", "ssl_support").ok().flatten().unwrap_or(true),
        }
    }
}

impl Default for ConfigParser {
    fn default() -> Self {
        Self::new()
    }
}
