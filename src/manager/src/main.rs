//! Frame Manager Daemon
//!
//! Central service orchestrator for Frame instances on cPanel servers.
//! Manages per-user Frame instances, port allocation, health monitoring,
//! and provides an HTTP API for WHM/cPanel integration.

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

use frame_manager::{config::Config, manager::FrameManager};

/// Frame Service Manager for cPanel
#[derive(Parser)]
#[command(name = "frame-manager")]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Configuration file path
    #[arg(short, long, default_value = "/etc/frame/frame.conf")]
    config: PathBuf,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, default_value = "info")]
    log_level: String,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the Frame manager daemon
    Start,

    /// Stop the Frame manager daemon
    Stop,

    /// Restart the Frame manager daemon
    Restart,

    /// Show service status
    Status,

    /// User instance management
    User {
        #[command(subcommand)]
        action: UserCommands,
    },

    /// Port management
    Port {
        #[command(subcommand)]
        action: PortCommands,
    },

    /// Show statistics
    Stats {
        /// Stat type (memory, cpu, instances)
        stat_type: Option<String>,
    },

    /// Reload configuration
    Reload,
}

#[derive(Subcommand)]
enum UserCommands {
    /// Start a user's Frame instance
    Start {
        /// Username
        username: String,
    },
    /// Stop a user's Frame instance
    Stop {
        /// Username
        username: String,
    },
    /// Restart a user's Frame instance
    Restart {
        /// Username
        username: String,
    },
    /// Show user instance status
    Status {
        /// Username
        username: String,
    },
    /// List all user instances
    List,
}

#[derive(Subcommand)]
enum PortCommands {
    /// Allocate a port for a user
    Allocate {
        /// Username
        username: String,
    },
    /// Release a user's allocated port
    Release {
        /// Username
        username: String,
    },
    /// List all port allocations
    List,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize logging
    let log_level = match cli.log_level.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    };

    let subscriber = FmtSubscriber::builder()
        .with_max_level(log_level)
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .init();

    info!("Frame Manager starting...");
    info!("Configuration file: {}", cli.config.display());

    // Load configuration
    let config = Config::load(&cli.config)?;
    info!("Configuration loaded successfully");

    // Create manager instance
    let manager = FrameManager::new(config).await?;

    // Handle commands
    match cli.command {
        None | Some(Commands::Start) => {
            info!("Starting Frame Manager daemon...");
            manager.run().await?;
        }
        Some(Commands::Stop) => {
            info!("Stopping Frame Manager daemon...");
            manager.stop().await?;
        }
        Some(Commands::Restart) => {
            info!("Restarting Frame Manager daemon...");
            manager.stop().await?;
            manager.run().await?;
        }
        Some(Commands::Status) => {
            let status = manager.status().await?;
            println!("{}", serde_json::to_string_pretty(&status)?);
        }
        Some(Commands::User { action }) => match action {
            UserCommands::Start { username } => {
                info!("Starting instance for user: {}", username);
                manager.start_instance(&username).await?;
                println!("Instance started for user: {}", username);
            }
            UserCommands::Stop { username } => {
                info!("Stopping instance for user: {}", username);
                manager.stop_instance(&username).await?;
                println!("Instance stopped for user: {}", username);
            }
            UserCommands::Restart { username } => {
                info!("Restarting instance for user: {}", username);
                manager.restart_instance(&username).await?;
                println!("Instance restarted for user: {}", username);
            }
            UserCommands::Status { username } => {
                let status = manager.instance_status(&username).await?;
                println!("{}", serde_json::to_string_pretty(&status)?);
            }
            UserCommands::List => {
                let instances = manager.list_instances().await?;
                println!("{}", serde_json::to_string_pretty(&instances)?);
            }
        },
        Some(Commands::Port { action }) => match action {
            PortCommands::Allocate { username } => {
                let port = manager.allocate_port(&username).await?;
                println!("Allocated port {} for user: {}", port, username);
            }
            PortCommands::Release { username } => {
                manager.release_port(&username).await?;
                println!("Released port for user: {}", username);
            }
            PortCommands::List => {
                let ports = manager.list_ports().await?;
                println!("{}", serde_json::to_string_pretty(&ports)?);
            }
        },
        Some(Commands::Stats { stat_type }) => {
            let stats = manager.stats(stat_type.as_deref()).await?;
            println!("{}", serde_json::to_string_pretty(&stats)?);
        }
        Some(Commands::Reload) => {
            info!("Reloading configuration...");
            manager.reload_config().await?;
            println!("Configuration reloaded");
        }
    }

    Ok(())
}
