//! HTTP API Module
//!
//! Internal HTTP API for WHM/cPanel integration.

pub mod handlers;
pub mod routes;

use anyhow::Result;
use axum::Router;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;

pub use handlers::*;
pub use routes::*;

use crate::manager::FrameManager;

/// API server
pub struct ApiServer {
    port: u16,
    manager: Arc<FrameManager>,
    running: Arc<RwLock<bool>>,
}

impl ApiServer {
    /// Create a new API server
    pub fn new(port: u16, manager: Arc<FrameManager>) -> Self {
        Self {
            port,
            manager,
            running: Arc::new(RwLock::new(false)),
        }
    }

    /// Start the API server
    pub async fn start(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }
        *running = true;
        drop(running);

        let app = create_router(Arc::clone(&self.manager));
        let addr = SocketAddr::from(([127, 0, 0, 1], self.port));

        tracing::info!("API server listening on http://{}", addr);

        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app).await?;

        Ok(())
    }

    /// Stop the API server (graceful shutdown would need more work)
    pub async fn stop(&self) {
        let mut running = self.running.write().await;
        *running = false;
        tracing::info!("API server stopped");
    }
}

/// Create the router with all routes
fn create_router(manager: Arc<FrameManager>) -> Router {
    routes::create_routes(manager)
}
