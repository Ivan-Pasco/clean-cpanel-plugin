//! Port Allocation Module
//!
//! Manages dynamic port allocation for user Frame instances.

mod registry;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;

pub use registry::PortRegistry;

/// Port allocation manager
pub struct PortAllocator {
    /// Port range start
    range_start: u16,
    /// Port range end
    range_end: u16,
    /// Registry for persistent storage
    registry: Arc<RwLock<PortRegistry>>,
}

/// Port allocation entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortAllocation {
    pub username: String,
    pub port: u16,
    pub allocated_at: chrono::DateTime<chrono::Utc>,
}

impl PortAllocator {
    /// Create a new port allocator
    pub fn new(range_start: u16, range_end: u16, registry_path: &Path) -> Result<Self> {
        let registry = PortRegistry::load(registry_path)?;

        Ok(Self {
            range_start,
            range_end,
            registry: Arc::new(RwLock::new(registry)),
        })
    }

    /// Allocate a port for a user
    pub async fn allocate(&self, username: &str) -> Result<u16> {
        let mut registry = self.registry.write().await;

        // Check if user already has a port
        if let Some(port) = registry.get_port(username) {
            return Ok(port);
        }

        // Try to reuse a released port first
        if let Some(port) = registry.pop_released() {
            registry.allocate(username, port)?;
            registry.save()?;
            return Ok(port);
        }

        // Find next available port
        let port = self.find_available_port(&registry)?;
        registry.allocate(username, port)?;
        registry.save()?;

        Ok(port)
    }

    /// Release a user's port allocation
    pub async fn release(&self, username: &str) -> Result<()> {
        let mut registry = self.registry.write().await;
        registry.release(username)?;
        registry.save()?;
        Ok(())
    }

    /// Get port for a user
    pub async fn get_port(&self, username: &str) -> Option<u16> {
        let registry = self.registry.read().await;
        registry.get_port(username)
    }

    /// List all port allocations
    pub async fn list_allocations(&self) -> HashMap<String, u16> {
        let registry = self.registry.read().await;
        registry.allocated.clone()
    }

    /// Check if a port is available
    pub async fn is_available(&self, port: u16) -> bool {
        if port < self.range_start || port > self.range_end {
            return false;
        }

        let registry = self.registry.read().await;
        !registry.allocated.values().any(|&p| p == port)
    }

    /// Find an available port
    fn find_available_port(&self, registry: &PortRegistry) -> Result<u16> {
        for port in self.range_start..=self.range_end {
            if !registry.allocated.values().any(|&p| p == port) {
                // Also check if port is in use on the system
                if !is_port_in_use(port) {
                    return Ok(port);
                }
            }
        }

        anyhow::bail!(
            "No available ports in range {}-{}",
            self.range_start,
            self.range_end
        )
    }

    /// Get statistics
    pub async fn stats(&self) -> PortStats {
        let registry = self.registry.read().await;
        let total = (self.range_end - self.range_start + 1) as usize;
        let allocated = registry.allocated.len();
        let released = registry.released.len();

        PortStats {
            range_start: self.range_start,
            range_end: self.range_end,
            total,
            allocated,
            available: total - allocated,
            released_pool: released,
        }
    }
}

/// Port allocation statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortStats {
    pub range_start: u16,
    pub range_end: u16,
    pub total: usize,
    pub allocated: usize,
    pub available: usize,
    pub released_pool: usize,
}

/// Check if a port is in use on the system
fn is_port_in_use(port: u16) -> bool {
    use std::net::TcpListener;
    TcpListener::bind(("127.0.0.1", port)).is_err()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_port_allocation() {
        let dir = tempdir().unwrap();
        let registry_path = dir.path().join("ports.json");

        let allocator = PortAllocator::new(30001, 30100, &registry_path).unwrap();

        // Allocate port for user1
        let port1 = allocator.allocate("user1").await.unwrap();
        assert!(port1 >= 30001 && port1 <= 30100);

        // Same user should get same port
        let port1_again = allocator.allocate("user1").await.unwrap();
        assert_eq!(port1, port1_again);

        // Different user gets different port
        let port2 = allocator.allocate("user2").await.unwrap();
        assert_ne!(port1, port2);

        // Release port
        allocator.release("user1").await.unwrap();
        assert!(allocator.get_port("user1").await.is_none());
    }
}
