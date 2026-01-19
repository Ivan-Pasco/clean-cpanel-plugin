//! Resource Limits
//!
//! Defines and enforces resource limits for Frame instances.

use serde::{Deserialize, Serialize};

/// Resource limits for a Frame instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    /// Memory limit in MB
    pub memory_mb: u64,
    /// CPU limit (percentage 0-100)
    pub cpu_percent: u8,
    /// Maximum concurrent connections
    pub max_connections: u32,
    /// Maximum number of apps
    pub max_apps: u32,
    /// Disk quota in MB
    pub disk_quota_mb: u64,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            memory_mb: 512,
            cpu_percent: 25,
            max_connections: 100,
            max_apps: 5,
            disk_quota_mb: 1024,
        }
    }
}

impl ResourceLimits {
    /// Create limits from configuration defaults
    pub fn from_defaults(memory: u64, cpu: u8, max_apps: u32, disk: u64) -> Self {
        Self {
            memory_mb: memory,
            cpu_percent: cpu,
            max_connections: 100,
            max_apps,
            disk_quota_mb: disk,
        }
    }

    /// Memory limit in bytes
    pub fn memory_bytes(&self) -> u64 {
        self.memory_mb * 1024 * 1024
    }

    /// Disk quota in bytes
    pub fn disk_quota_bytes(&self) -> u64 {
        self.disk_quota_mb * 1024 * 1024
    }

    /// Validate limits
    pub fn validate(&self) -> Result<(), String> {
        if self.memory_mb == 0 {
            return Err("Memory limit must be greater than 0".to_string());
        }
        if self.cpu_percent > 100 {
            return Err("CPU limit must be between 0 and 100".to_string());
        }
        if self.max_apps == 0 {
            return Err("Max apps must be greater than 0".to_string());
        }
        Ok(())
    }
}

/// cgroups v2 resource controller
#[cfg(target_os = "linux")]
pub struct CgroupController {
    cgroup_path: std::path::PathBuf,
}

#[cfg(target_os = "linux")]
impl CgroupController {
    /// Create a new cgroup for a user
    pub fn create_for_user(username: &str) -> std::io::Result<Self> {
        let cgroup_path = std::path::PathBuf::from(format!("/sys/fs/cgroup/frame/{}", username));
        std::fs::create_dir_all(&cgroup_path)?;

        Ok(Self { cgroup_path })
    }

    /// Apply memory limit
    pub fn set_memory_limit(&self, limit_bytes: u64) -> std::io::Result<()> {
        let memory_max = self.cgroup_path.join("memory.max");
        std::fs::write(memory_max, limit_bytes.to_string())?;
        Ok(())
    }

    /// Apply CPU limit (as percentage of one core)
    pub fn set_cpu_limit(&self, percent: u8) -> std::io::Result<()> {
        // cpu.max format: "quota period"
        // For 25% of one CPU: "25000 100000"
        let quota = (percent as u64) * 1000;
        let period = 100000u64;
        let cpu_max = self.cgroup_path.join("cpu.max");
        std::fs::write(cpu_max, format!("{} {}", quota, period))?;
        Ok(())
    }

    /// Add a process to this cgroup
    pub fn add_process(&self, pid: u32) -> std::io::Result<()> {
        let procs = self.cgroup_path.join("cgroup.procs");
        std::fs::write(procs, pid.to_string())?;
        Ok(())
    }

    /// Remove the cgroup
    pub fn remove(&self) -> std::io::Result<()> {
        // Move all processes to parent first
        let procs = self.cgroup_path.join("cgroup.procs");
        if procs.exists() {
            let content = std::fs::read_to_string(&procs)?;
            let parent_procs =
                self.cgroup_path.parent().unwrap().join("cgroup.procs");
            for line in content.lines() {
                let _ = std::fs::write(&parent_procs, line);
            }
        }

        std::fs::remove_dir(&self.cgroup_path)?;
        Ok(())
    }
}

/// Placeholder for non-Linux systems
#[cfg(not(target_os = "linux"))]
pub struct CgroupController;

#[cfg(not(target_os = "linux"))]
impl CgroupController {
    pub fn create_for_user(_username: &str) -> std::io::Result<Self> {
        Ok(Self)
    }

    pub fn set_memory_limit(&self, _limit_bytes: u64) -> std::io::Result<()> {
        Ok(())
    }

    pub fn set_cpu_limit(&self, _percent: u8) -> std::io::Result<()> {
        Ok(())
    }

    pub fn add_process(&self, _pid: u32) -> std::io::Result<()> {
        Ok(())
    }

    pub fn remove(&self) -> std::io::Result<()> {
        Ok(())
    }
}
