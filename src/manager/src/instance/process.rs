//! Process Management
//!
//! Handles spawning and managing Frame server processes.

use anyhow::{Context, Result};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use std::path::Path;
use std::process::Stdio;
use tokio::process::Command;

use super::ResourceLimits;

/// Process manager for Frame server instances
pub struct ProcessManager;

impl ProcessManager {
    pub fn new() -> Self {
        Self
    }

    /// Spawn a new Frame server process for a user
    pub async fn spawn(
        &self,
        username: &str,
        frame_server_path: &Path,
        port: u16,
        instance_dir: &Path,
        limits: &ResourceLimits,
    ) -> Result<u32> {
        let apps_dir = instance_dir.join("apps");
        let data_dir = instance_dir.join("data");
        let log_file = instance_dir.join("logs").join("frame.log");

        // Ensure log directory exists
        if let Some(parent) = log_file.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        // Build command with sudo to run as the user
        let mut cmd = Command::new("sudo");
        cmd.args(["-u", username])
            .arg(frame_server_path)
            .args(["--port", &port.to_string()])
            .args(["--app-dir", apps_dir.to_str().unwrap()])
            .args(["--data-dir", data_dir.to_str().unwrap()])
            .args(["--memory-limit", &limits.memory_mb.to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());

        // Set resource limits via environment
        cmd.env("FRAME_MEMORY_LIMIT_MB", limits.memory_mb.to_string());
        cmd.env("FRAME_CPU_LIMIT_PERCENT", limits.cpu_percent.to_string());
        cmd.env("FRAME_MAX_CONNECTIONS", limits.max_connections.to_string());

        let child = cmd
            .spawn()
            .with_context(|| format!("Failed to spawn Frame server for user {}", username))?;

        let pid = child
            .id()
            .ok_or_else(|| anyhow::anyhow!("Failed to get process ID"))?;

        // Wait briefly and check if process is still running
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        if !self.is_running(pid) {
            anyhow::bail!("Frame server process exited immediately for user {}", username);
        }

        Ok(pid)
    }

    /// Stop a process
    pub async fn stop(&self, pid: u32) -> Result<()> {
        let nix_pid = Pid::from_raw(pid as i32);

        // First try SIGTERM for graceful shutdown
        if let Err(e) = kill(nix_pid, Signal::SIGTERM) {
            if e == nix::errno::Errno::ESRCH {
                // Process already dead
                return Ok(());
            }
            tracing::warn!("Failed to send SIGTERM to PID {}: {}", pid, e);
        }

        // Wait for graceful shutdown
        for _ in 0..50 {
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
            if !self.is_running(pid) {
                return Ok(());
            }
        }

        // Force kill if still running
        tracing::warn!("Process {} did not stop gracefully, sending SIGKILL", pid);
        if let Err(e) = kill(nix_pid, Signal::SIGKILL) {
            if e != nix::errno::Errno::ESRCH {
                anyhow::bail!("Failed to kill process {}: {}", pid, e);
            }
        }

        Ok(())
    }

    /// Check if a process is running
    pub fn is_running(&self, pid: u32) -> bool {
        let nix_pid = Pid::from_raw(pid as i32);
        kill(nix_pid, None).is_ok()
    }

    /// Get resource usage for a process
    pub fn get_resource_usage(&self, pid: u32) -> Result<(u64, f32)> {
        // Read from /proc on Linux
        #[cfg(target_os = "linux")]
        {
            let statm_path = format!("/proc/{}/statm", pid);
            let stat_path = format!("/proc/{}/stat", pid);

            // Get memory usage (RSS in pages)
            let statm = std::fs::read_to_string(&statm_path)
                .with_context(|| format!("Failed to read {}", statm_path))?;
            let parts: Vec<&str> = statm.split_whitespace().collect();
            let rss_pages: u64 = parts.get(1).unwrap_or(&"0").parse().unwrap_or(0);
            let page_size = 4096u64; // Typical page size
            let memory_bytes = rss_pages * page_size;

            // Get CPU usage (simplified - would need sampling for accurate %)
            let stat = std::fs::read_to_string(&stat_path)
                .with_context(|| format!("Failed to read {}", stat_path))?;
            let stat_parts: Vec<&str> = stat.split_whitespace().collect();
            let utime: u64 = stat_parts.get(13).unwrap_or(&"0").parse().unwrap_or(0);
            let stime: u64 = stat_parts.get(14).unwrap_or(&"0").parse().unwrap_or(0);
            let total_time = (utime + stime) as f32;
            // This is simplified - real implementation would track over time
            let cpu_percent = (total_time / 100.0).min(100.0);

            return Ok((memory_bytes, cpu_percent));
        }

        // Fallback for non-Linux
        #[cfg(not(target_os = "linux"))]
        {
            Ok((0, 0.0))
        }
    }
}

impl Default for ProcessManager {
    fn default() -> Self {
        Self::new()
    }
}
