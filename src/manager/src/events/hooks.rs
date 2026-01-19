//! Hook Execution

use std::path::PathBuf;
use tokio::process::Command;

use super::Event;

/// Hook script executor
pub struct HookExecutor {
    hooks_dir: PathBuf,
}

impl HookExecutor {
    /// Create a new hook executor
    pub fn new(hooks_dir: PathBuf) -> Self {
        Self { hooks_dir }
    }

    /// Execute hooks for an event
    pub async fn execute(&self, event: &Event) {
        let hook_name = match event {
            Event::InstanceStarted { .. } => "on_instance_started",
            Event::InstanceStopped { .. } => "on_instance_stopped",
            Event::InstanceCrashed { .. } => "on_instance_crashed",
            Event::AppDeployed { .. } => "on_app_deployed",
            Event::AppRemoved { .. } => "on_app_removed",
            Event::ResourceLimitReached { .. } => "on_resource_limit",
            Event::HealthCheckFailed { .. } => "on_health_check_failed",
            Event::ConfigReloaded => "on_config_reloaded",
            Event::ServiceStarted => "on_service_started",
            Event::ServiceStopped => "on_service_stopped",
        };

        let hook_path = self.hooks_dir.join(hook_name);

        if !hook_path.exists() {
            return;
        }

        // Build environment variables from event
        let env_vars = self.event_to_env(event);

        match Command::new(&hook_path)
            .envs(env_vars)
            .output()
            .await
        {
            Ok(output) => {
                if !output.status.success() {
                    tracing::warn!(
                        "Hook {} failed with status {}: {}",
                        hook_name,
                        output.status,
                        String::from_utf8_lossy(&output.stderr)
                    );
                } else {
                    tracing::debug!("Hook {} executed successfully", hook_name);
                }
            }
            Err(e) => {
                tracing::error!("Failed to execute hook {}: {}", hook_name, e);
            }
        }
    }

    /// Convert event to environment variables
    fn event_to_env(&self, event: &Event) -> Vec<(String, String)> {
        let mut env = Vec::new();

        match event {
            Event::InstanceStarted { username, port, apps } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                env.push(("FRAME_PORT".to_string(), port.to_string()));
                env.push(("FRAME_APPS".to_string(), apps.join(",")));
            }
            Event::InstanceStopped { username } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
            }
            Event::InstanceCrashed {
                username,
                exit_code,
                reason,
            } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                if let Some(code) = exit_code {
                    env.push(("FRAME_EXIT_CODE".to_string(), code.to_string()));
                }
                env.push(("FRAME_REASON".to_string(), reason.clone()));
            }
            Event::AppDeployed { username, app_name } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                env.push(("FRAME_APP_NAME".to_string(), app_name.clone()));
            }
            Event::AppRemoved { username, app_name } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                env.push(("FRAME_APP_NAME".to_string(), app_name.clone()));
            }
            Event::ResourceLimitReached {
                username,
                resource,
                current,
                limit,
            } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                env.push(("FRAME_RESOURCE".to_string(), resource.clone()));
                env.push(("FRAME_CURRENT".to_string(), current.to_string()));
                env.push(("FRAME_LIMIT".to_string(), limit.to_string()));
            }
            Event::HealthCheckFailed {
                username,
                check_name,
                message,
            } => {
                env.push(("FRAME_USERNAME".to_string(), username.clone()));
                env.push(("FRAME_CHECK_NAME".to_string(), check_name.clone()));
                env.push(("FRAME_MESSAGE".to_string(), message.clone()));
            }
            Event::ConfigReloaded | Event::ServiceStarted | Event::ServiceStopped => {}
        }

        env
    }
}
