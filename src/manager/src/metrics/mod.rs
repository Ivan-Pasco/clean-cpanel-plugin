//! Metrics Collection Module
//!
//! Collects and exports metrics in Prometheus format.

mod prometheus;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub use prometheus::PrometheusExporter;

/// Metrics collector
pub struct MetricsCollector {
    /// Collected metrics
    metrics: HashMap<String, Metric>,
}

/// A single metric
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Metric {
    pub name: String,
    pub help: String,
    pub metric_type: MetricType,
    pub values: Vec<MetricValue>,
}

/// Metric types
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    Summary,
}

/// A metric value with optional labels
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricValue {
    pub value: f64,
    pub labels: HashMap<String, String>,
}

impl MetricsCollector {
    /// Create a new metrics collector
    pub fn new() -> Self {
        Self {
            metrics: HashMap::new(),
        }
    }

    /// Register a new metric
    pub fn register(&mut self, name: &str, help: &str, metric_type: MetricType) {
        self.metrics.insert(
            name.to_string(),
            Metric {
                name: name.to_string(),
                help: help.to_string(),
                metric_type,
                values: Vec::new(),
            },
        );
    }

    /// Set a gauge value
    pub fn set_gauge(&mut self, name: &str, value: f64, labels: HashMap<String, String>) {
        if let Some(metric) = self.metrics.get_mut(name) {
            // Find existing value with same labels or add new
            if let Some(existing) = metric
                .values
                .iter_mut()
                .find(|v| v.labels == labels)
            {
                existing.value = value;
            } else {
                metric.values.push(MetricValue { value, labels });
            }
        }
    }

    /// Increment a counter
    pub fn inc_counter(&mut self, name: &str, labels: HashMap<String, String>) {
        self.add_counter(name, 1.0, labels);
    }

    /// Add to a counter
    pub fn add_counter(&mut self, name: &str, value: f64, labels: HashMap<String, String>) {
        if let Some(metric) = self.metrics.get_mut(name) {
            if let Some(existing) = metric
                .values
                .iter_mut()
                .find(|v| v.labels == labels)
            {
                existing.value += value;
            } else {
                metric.values.push(MetricValue { value, labels });
            }
        }
    }

    /// Get all metrics
    pub fn get_all(&self) -> &HashMap<String, Metric> {
        &self.metrics
    }

    /// Clear all metric values
    pub fn clear(&mut self) {
        for metric in self.metrics.values_mut() {
            metric.values.clear();
        }
    }

    /// Export to Prometheus format
    pub fn export_prometheus(&self) -> String {
        PrometheusExporter::export(&self.metrics)
    }
}

impl Default for MetricsCollector {
    fn default() -> Self {
        let mut collector = Self::new();

        // Register standard metrics
        collector.register(
            "frame_instances_total",
            "Total number of Frame instances",
            MetricType::Gauge,
        );
        collector.register(
            "frame_instances_running",
            "Number of running Frame instances",
            MetricType::Gauge,
        );
        collector.register(
            "frame_instances_stopped",
            "Number of stopped Frame instances",
            MetricType::Gauge,
        );
        collector.register(
            "frame_memory_usage_bytes",
            "Memory usage per instance in bytes",
            MetricType::Gauge,
        );
        collector.register(
            "frame_cpu_usage_percent",
            "CPU usage per instance as percentage",
            MetricType::Gauge,
        );
        collector.register(
            "frame_requests_total",
            "Total requests per instance",
            MetricType::Counter,
        );
        collector.register(
            "frame_request_duration_seconds",
            "Request duration histogram",
            MetricType::Histogram,
        );
        collector.register(
            "frame_apps_total",
            "Total number of deployed apps",
            MetricType::Gauge,
        );
        collector.register(
            "frame_ports_allocated",
            "Number of allocated ports",
            MetricType::Gauge,
        );
        collector.register(
            "frame_ports_available",
            "Number of available ports",
            MetricType::Gauge,
        );
        collector.register(
            "frame_health_check_failures",
            "Number of health check failures",
            MetricType::Counter,
        );

        collector
    }
}

/// Instance metrics snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstanceMetrics {
    pub username: String,
    pub memory_bytes: u64,
    pub cpu_percent: f32,
    pub requests_total: u64,
    pub app_count: u32,
}
