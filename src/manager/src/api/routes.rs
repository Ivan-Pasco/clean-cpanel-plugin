//! API Route Definitions

use axum::{
    extract::{Path, State},
    routing::{get, post, put},
    Json, Router,
};
use std::sync::Arc;

use super::handlers::*;
use crate::manager::FrameManager;

/// State type for handlers
pub type AppState = Arc<FrameManager>;

/// Create all API routes
pub fn create_routes(manager: Arc<FrameManager>) -> Router {
    Router::new()
        // Service endpoints
        .route("/frame/status", get(get_status))
        .route("/frame/restart", post(restart_service))
        // Instance endpoints
        .route("/frame/instances", get(list_instances))
        .route("/frame/instances/:username/start", post(start_instance))
        .route("/frame/instances/:username/stop", post(stop_instance))
        .route("/frame/instances/:username/restart", post(restart_instance))
        .route("/frame/instances/:username/logs", get(get_instance_logs))
        .route("/frame/instances/:username/status", get(get_instance_status))
        // Settings endpoints
        .route("/frame/settings", get(get_settings).put(update_settings))
        // Package endpoints
        .route("/frame/packages", get(list_packages))
        .route("/frame/packages/:name", put(update_package))
        // Port endpoints
        .route("/frame/ports", get(list_ports))
        // Metrics endpoint
        .route("/metrics", get(get_metrics))
        // Health endpoint
        .route("/health", get(health_check))
        .with_state(manager)
}
