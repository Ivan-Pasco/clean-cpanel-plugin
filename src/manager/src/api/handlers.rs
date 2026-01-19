//! API Request Handlers

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::manager::FrameManager;

/// Standard API response wrapper
#[derive(Serialize)]
pub struct ApiResponse<T> {
    pub status: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub errors: Vec<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            status: 1,
            data: Some(data),
            errors: Vec::new(),
        }
    }

    pub fn error(message: &str) -> ApiResponse<()> {
        ApiResponse {
            status: 0,
            data: None,
            errors: vec![message.to_string()],
        }
    }
}

/// Service status response
#[derive(Serialize)]
pub struct ServiceStatus {
    pub service_status: String,
    pub instances_running: usize,
    pub instances_total: usize,
    pub memory_usage_mb: u64,
    pub port_range: String,
}

/// Instance status response
#[derive(Serialize)]
pub struct InstanceStatusResponse {
    pub username: String,
    pub status: String,
    pub port: u16,
    pub memory_usage_mb: u64,
    pub cpu_usage: f32,
    pub app_count: u32,
}

/// Settings update request
#[derive(Deserialize)]
pub struct SettingsUpdate {
    pub enabled: Option<bool>,
    pub auto_start: Option<bool>,
    pub health_check_interval: Option<u64>,
}

/// Package update request
#[derive(Deserialize)]
pub struct PackageUpdate {
    pub memory_limit: Option<u64>,
    pub cpu_limit: Option<u8>,
    pub max_apps: Option<u32>,
    pub disk_quota: Option<u64>,
}

// ============ Handlers ============

/// Get service status
pub async fn get_status(
    State(manager): State<Arc<FrameManager>>,
) -> Json<ApiResponse<ServiceStatus>> {
    match manager.status().await {
        Ok(status) => Json(ApiResponse::success(status)),
        Err(e) => Json(ApiResponse {
            status: 0,
            data: None,
            errors: vec![e.to_string()],
        }),
    }
}

/// Restart the service
pub async fn restart_service(
    State(manager): State<Arc<FrameManager>>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    // This would typically restart all instances
    match manager.restart_all().await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success("Service restarted".to_string())),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// List all instances
pub async fn list_instances(
    State(manager): State<Arc<FrameManager>>,
) -> Json<ApiResponse<Vec<InstanceStatusResponse>>> {
    match manager.list_instances().await {
        Ok(instances) => Json(ApiResponse::success(instances)),
        Err(e) => Json(ApiResponse {
            status: 0,
            data: None,
            errors: vec![e.to_string()],
        }),
    }
}

/// Start a user instance
pub async fn start_instance(
    State(manager): State<Arc<FrameManager>>,
    Path(username): Path<String>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    match manager.start_instance(&username).await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success(format!("Instance started for {}", username))),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// Stop a user instance
pub async fn stop_instance(
    State(manager): State<Arc<FrameManager>>,
    Path(username): Path<String>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    match manager.stop_instance(&username).await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success(format!("Instance stopped for {}", username))),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// Restart a user instance
pub async fn restart_instance(
    State(manager): State<Arc<FrameManager>>,
    Path(username): Path<String>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    match manager.restart_instance(&username).await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success(format!("Instance restarted for {}", username))),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// Get instance logs
pub async fn get_instance_logs(
    State(manager): State<Arc<FrameManager>>,
    Path(username): Path<String>,
) -> (StatusCode, Json<ApiResponse<Vec<String>>>) {
    match manager.get_logs(&username, 100).await {
        Ok(logs) => (StatusCode::OK, Json(ApiResponse::success(logs))),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// Get instance status
pub async fn get_instance_status(
    State(manager): State<Arc<FrameManager>>,
    Path(username): Path<String>,
) -> (StatusCode, Json<ApiResponse<InstanceStatusResponse>>) {
    match manager.instance_status(&username).await {
        Ok(status) => (StatusCode::OK, Json(ApiResponse::success(status))),
        Err(e) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// Get settings
pub async fn get_settings(
    State(manager): State<Arc<FrameManager>>,
) -> Json<ApiResponse<serde_json::Value>> {
    match manager.get_settings().await {
        Ok(settings) => Json(ApiResponse::success(settings)),
        Err(e) => Json(ApiResponse {
            status: 0,
            data: None,
            errors: vec![e.to_string()],
        }),
    }
}

/// Update settings
pub async fn update_settings(
    State(manager): State<Arc<FrameManager>>,
    Json(update): Json<SettingsUpdate>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    match manager.update_settings(update).await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success("Settings updated".to_string())),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// List packages
pub async fn list_packages(
    State(manager): State<Arc<FrameManager>>,
) -> Json<ApiResponse<Vec<serde_json::Value>>> {
    match manager.list_packages().await {
        Ok(packages) => Json(ApiResponse::success(packages)),
        Err(e) => Json(ApiResponse {
            status: 0,
            data: None,
            errors: vec![e.to_string()],
        }),
    }
}

/// Update package
pub async fn update_package(
    State(manager): State<Arc<FrameManager>>,
    Path(name): Path<String>,
    Json(update): Json<PackageUpdate>,
) -> (StatusCode, Json<ApiResponse<String>>) {
    match manager.update_package(&name, update).await {
        Ok(_) => (
            StatusCode::OK,
            Json(ApiResponse::success(format!("Package {} updated", name))),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                status: 0,
                data: None,
                errors: vec![e.to_string()],
            }),
        ),
    }
}

/// List port allocations
pub async fn list_ports(
    State(manager): State<Arc<FrameManager>>,
) -> Json<ApiResponse<serde_json::Value>> {
    match manager.list_ports().await {
        Ok(ports) => Json(ApiResponse::success(ports)),
        Err(e) => Json(ApiResponse {
            status: 0,
            data: None,
            errors: vec![e.to_string()],
        }),
    }
}

/// Get Prometheus metrics
pub async fn get_metrics(State(manager): State<Arc<FrameManager>>) -> String {
    match manager.get_metrics().await {
        Ok(metrics) => metrics,
        Err(e) => format!("# Error collecting metrics: {}", e),
    }
}

/// Health check endpoint
pub async fn health_check() -> (StatusCode, &'static str) {
    (StatusCode::OK, "OK")
}
