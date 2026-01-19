//! Port Registry - Persistent storage for port allocations

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Persistent port registry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortRegistry {
    /// Path to the registry file
    #[serde(skip)]
    path: PathBuf,

    /// Port range configuration
    pub range: PortRange,

    /// Currently allocated ports (username -> port)
    pub allocated: HashMap<String, u16>,

    /// Released ports available for reuse
    pub released: Vec<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortRange {
    pub start: u16,
    pub end: u16,
}

impl Default for PortRange {
    fn default() -> Self {
        Self {
            start: 30001,
            end: 32000,
        }
    }
}

impl PortRegistry {
    /// Load registry from file or create new
    pub fn load(path: &Path) -> Result<Self> {
        if path.exists() {
            let content = fs::read_to_string(path)
                .with_context(|| format!("Failed to read port registry: {}", path.display()))?;

            let mut registry: PortRegistry = serde_json::from_str(&content)
                .with_context(|| "Failed to parse port registry JSON")?;

            registry.path = path.to_path_buf();
            Ok(registry)
        } else {
            Ok(Self {
                path: path.to_path_buf(),
                range: PortRange::default(),
                allocated: HashMap::new(),
                released: Vec::new(),
            })
        }
    }

    /// Save registry to file
    pub fn save(&self) -> Result<()> {
        // Ensure parent directory exists
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("Failed to create directory: {}", parent.display())
            })?;
        }

        let content = serde_json::to_string_pretty(self)
            .with_context(|| "Failed to serialize port registry")?;

        fs::write(&self.path, content)
            .with_context(|| format!("Failed to write port registry: {}", self.path.display()))?;

        Ok(())
    }

    /// Get port for a user
    pub fn get_port(&self, username: &str) -> Option<u16> {
        self.allocated.get(username).copied()
    }

    /// Allocate a port to a user
    pub fn allocate(&mut self, username: &str, port: u16) -> Result<()> {
        // Check if port is already allocated
        if self.allocated.values().any(|&p| p == port) {
            anyhow::bail!("Port {} is already allocated", port);
        }

        // Remove from released pool if present
        self.released.retain(|&p| p != port);

        // Add allocation
        self.allocated.insert(username.to_string(), port);

        Ok(())
    }

    /// Release a user's port
    pub fn release(&mut self, username: &str) -> Result<()> {
        if let Some(port) = self.allocated.remove(username) {
            // Add to released pool for reuse
            if !self.released.contains(&port) {
                self.released.push(port);
            }
            Ok(())
        } else {
            anyhow::bail!("No port allocated for user: {}", username)
        }
    }

    /// Pop a released port for reuse
    pub fn pop_released(&mut self) -> Option<u16> {
        self.released.pop()
    }

    /// Get count of allocated ports
    pub fn allocated_count(&self) -> usize {
        self.allocated.len()
    }

    /// Get count of released ports in pool
    pub fn released_count(&self) -> usize {
        self.released.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_registry_persistence() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ports.json");

        // Create and save
        {
            let mut registry = PortRegistry::load(&path).unwrap();
            registry.allocate("user1", 30001).unwrap();
            registry.allocate("user2", 30002).unwrap();
            registry.save().unwrap();
        }

        // Load and verify
        {
            let registry = PortRegistry::load(&path).unwrap();
            assert_eq!(registry.get_port("user1"), Some(30001));
            assert_eq!(registry.get_port("user2"), Some(30002));
            assert_eq!(registry.allocated_count(), 2);
        }
    }

    #[test]
    fn test_port_release_and_reuse() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ports.json");

        let mut registry = PortRegistry::load(&path).unwrap();

        registry.allocate("user1", 30001).unwrap();
        registry.release("user1").unwrap();

        assert!(registry.get_port("user1").is_none());
        assert_eq!(registry.pop_released(), Some(30001));
    }
}
