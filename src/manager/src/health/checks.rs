//! Health Check Implementations

use chrono::{DateTime, Utc};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use serde::{Deserialize, Serialize};
use std::net::TcpStream;
use std::time::Duration;

/// Health check definition
pub struct HealthCheck {
    check_type: CheckType,
}

enum CheckType {
    Process(u32),
    Port(u16),
    Http(u16, String),
    Memory(u32, u64),
}

/// Result of a health check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheckResult {
    pub check_name: String,
    pub passed: bool,
    pub message: String,
    pub duration_ms: u64,
    pub timestamp: DateTime<Utc>,
}

impl HealthCheck {
    /// Create a process liveness check
    pub fn process(pid: u32) -> Self {
        Self {
            check_type: CheckType::Process(pid),
        }
    }

    /// Create a port binding check
    pub fn port(port: u16) -> Self {
        Self {
            check_type: CheckType::Port(port),
        }
    }

    /// Create an HTTP endpoint check
    pub fn http(port: u16, path: &str) -> Self {
        Self {
            check_type: CheckType::Http(port, path.to_string()),
        }
    }

    /// Create a memory usage check
    pub fn memory(pid: u32, limit_bytes: u64) -> Self {
        Self {
            check_type: CheckType::Memory(pid, limit_bytes),
        }
    }

    /// Execute the health check
    pub async fn execute(&self) -> HealthCheckResult {
        let start = std::time::Instant::now();
        let (name, passed, message) = match &self.check_type {
            CheckType::Process(pid) => self.check_process(*pid),
            CheckType::Port(port) => self.check_port(*port),
            CheckType::Http(port, path) => self.check_http(*port, path).await,
            CheckType::Memory(pid, limit) => self.check_memory(*pid, *limit),
        };
        let duration_ms = start.elapsed().as_millis() as u64;

        HealthCheckResult {
            check_name: name,
            passed,
            message,
            duration_ms,
            timestamp: Utc::now(),
        }
    }

    fn check_process(&self, pid: u32) -> (String, bool, String) {
        let nix_pid = Pid::from_raw(pid as i32);
        let passed = kill(nix_pid, None).is_ok();
        let message = if passed {
            format!("Process {} is running", pid)
        } else {
            format!("Process {} is not running", pid)
        };
        ("process".to_string(), passed, message)
    }

    fn check_port(&self, port: u16) -> (String, bool, String) {
        let addr = format!("127.0.0.1:{}", port);
        match TcpStream::connect_timeout(
            &addr.parse().unwrap(),
            Duration::from_secs(2),
        ) {
            Ok(_) => (
                "port".to_string(),
                true,
                format!("Port {} is accepting connections", port),
            ),
            Err(e) => (
                "port".to_string(),
                false,
                format!("Port {} is not accessible: {}", port, e),
            ),
        }
    }

    async fn check_http(&self, port: u16, path: &str) -> (String, bool, String) {
        let url = format!("http://127.0.0.1:{}{}", port, path);

        // Simple HTTP check using TCP
        let addr = format!("127.0.0.1:{}", port);
        match TcpStream::connect_timeout(
            &addr.parse().unwrap(),
            Duration::from_secs(5),
        ) {
            Ok(mut stream) => {
                use std::io::{Read, Write};

                let request = format!(
                    "GET {} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
                    path
                );

                if stream.write_all(request.as_bytes()).is_err() {
                    return (
                        "http".to_string(),
                        false,
                        format!("Failed to send HTTP request to {}", url),
                    );
                }

                let mut response = String::new();
                if stream.read_to_string(&mut response).is_err() {
                    return (
                        "http".to_string(),
                        false,
                        format!("Failed to read HTTP response from {}", url),
                    );
                }

                // Check for 2xx status code
                if response.starts_with("HTTP/1.1 2") || response.starts_with("HTTP/1.0 2") {
                    (
                        "http".to_string(),
                        true,
                        format!("HTTP endpoint {} responded with success", url),
                    )
                } else {
                    let status_line = response.lines().next().unwrap_or("unknown");
                    (
                        "http".to_string(),
                        false,
                        format!("HTTP endpoint {} responded with: {}", url, status_line),
                    )
                }
            }
            Err(e) => (
                "http".to_string(),
                false,
                format!("Failed to connect to {}: {}", url, e),
            ),
        }
    }

    fn check_memory(&self, pid: u32, limit_bytes: u64) -> (String, bool, String) {
        #[cfg(target_os = "linux")]
        {
            let statm_path = format!("/proc/{}/statm", pid);
            match std::fs::read_to_string(&statm_path) {
                Ok(statm) => {
                    let parts: Vec<&str> = statm.split_whitespace().collect();
                    let rss_pages: u64 = parts.get(1).unwrap_or(&"0").parse().unwrap_or(0);
                    let page_size = 4096u64;
                    let memory_bytes = rss_pages * page_size;

                    let passed = memory_bytes <= limit_bytes;
                    let message = if passed {
                        format!(
                            "Memory usage {} MB is within limit {} MB",
                            memory_bytes / 1024 / 1024,
                            limit_bytes / 1024 / 1024
                        )
                    } else {
                        format!(
                            "Memory usage {} MB exceeds limit {} MB",
                            memory_bytes / 1024 / 1024,
                            limit_bytes / 1024 / 1024
                        )
                    };
                    ("memory".to_string(), passed, message)
                }
                Err(e) => (
                    "memory".to_string(),
                    false,
                    format!("Failed to read memory info: {}", e),
                ),
            }
        }

        #[cfg(not(target_os = "linux"))]
        {
            (
                "memory".to_string(),
                true,
                "Memory check not available on this platform".to_string(),
            )
        }
    }
}
