//! Prometheus Format Exporter

use std::collections::HashMap;

use super::{Metric, MetricType};

/// Prometheus format exporter
pub struct PrometheusExporter;

impl PrometheusExporter {
    /// Export metrics to Prometheus format
    pub fn export(metrics: &HashMap<String, Metric>) -> String {
        let mut output = String::new();

        for metric in metrics.values() {
            // Add HELP line
            output.push_str(&format!("# HELP {} {}\n", metric.name, metric.help));

            // Add TYPE line
            let type_str = match metric.metric_type {
                MetricType::Counter => "counter",
                MetricType::Gauge => "gauge",
                MetricType::Histogram => "histogram",
                MetricType::Summary => "summary",
            };
            output.push_str(&format!("# TYPE {} {}\n", metric.name, type_str));

            // Add values
            for value in &metric.values {
                if value.labels.is_empty() {
                    output.push_str(&format!("{} {}\n", metric.name, value.value));
                } else {
                    let labels: Vec<String> = value
                        .labels
                        .iter()
                        .map(|(k, v)| format!("{}=\"{}\"", k, Self::escape_label_value(v)))
                        .collect();
                    output.push_str(&format!(
                        "{}{{{}}} {}\n",
                        metric.name,
                        labels.join(","),
                        value.value
                    ));
                }
            }

            output.push('\n');
        }

        output
    }

    /// Escape special characters in label values
    fn escape_label_value(s: &str) -> String {
        s.replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::metrics::MetricValue;

    #[test]
    fn test_prometheus_export() {
        let mut metrics = HashMap::new();

        let mut gauge = Metric {
            name: "test_gauge".to_string(),
            help: "A test gauge".to_string(),
            metric_type: MetricType::Gauge,
            values: Vec::new(),
        };

        gauge.values.push(MetricValue {
            value: 42.0,
            labels: HashMap::new(),
        });

        let mut labels = HashMap::new();
        labels.insert("user".to_string(), "test_user".to_string());
        gauge.values.push(MetricValue {
            value: 100.0,
            labels,
        });

        metrics.insert("test_gauge".to_string(), gauge);

        let output = PrometheusExporter::export(&metrics);

        assert!(output.contains("# HELP test_gauge A test gauge"));
        assert!(output.contains("# TYPE test_gauge gauge"));
        assert!(output.contains("test_gauge 42"));
        assert!(output.contains("test_gauge{user=\"test_user\"} 100"));
    }
}
