//! Frame Manager Library
//!
//! Core functionality for the Frame Service Manager daemon.

pub mod api;
pub mod config;
pub mod events;
pub mod health;
pub mod instance;
pub mod manager;
pub mod metrics;
pub mod port;

pub use config::Config;
pub use manager::FrameManager;
