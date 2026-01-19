# Frame cPanel Plugin

A comprehensive cPanel/WHM plugin for hosting Clean Language/Frame web applications. This plugin enables hosting providers to offer WebAssembly-based application hosting through the familiar cPanel interface.

## Features

- **WHM Admin Interface**: Server-wide management of Frame instances
- **cPanel User Interface**: Self-service application deployment and management
- **Automatic Port Allocation**: Dynamic port assignment (30001-32000 range)
- **Process Management**: Health monitoring with automatic restart
- **Apache Integration**: Reverse proxy with SSL support
- **Resource Limits**: Per-user memory and CPU constraints
- **cPanel Hooks**: Automatic setup/cleanup on account creation/removal

## Requirements

- cPanel/WHM 102 or later
- CentOS/RHEL 7+ or CloudLinux
- Rust 1.70+ (for building from source)
- Apache with mod_proxy enabled
- Perl 5.26+ with Template Toolkit

## Quick Start

### Installation from Source

```bash
# Clone the repository
git clone https://github.com/cleanlanguage/clean-cpanel-plugin.git
cd clean-cpanel-plugin

# Build and install
make release
sudo make install
```

### Installation from RPM

```bash
# Download the RPM
curl -O https://releases.cleanlanguage.dev/frame-cpanel-1.0.0.rpm

# Install
sudo rpm -ivh frame-cpanel-1.0.0.rpm
```

### Verify Installation

```bash
# Check service status
sudo systemctl status frame-manager

# Validate installation
make validate
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        WHM Interface                         │
│              (Server-wide administration)                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                    Frame Manager Daemon                      │
│    - Port allocation    - Process management                │
│    - Health monitoring  - Resource enforcement              │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼───────┐ ┌───────▼───────┐ ┌───────▼───────┐
│  User Frame   │ │  User Frame   │ │  User Frame   │
│  Instance     │ │  Instance     │ │  Instance     │
│  (port 30001) │ │  (port 30002) │ │  (port 30003) │
└───────────────┘ └───────────────┘ └───────────────┘
        │                 │                 │
┌───────▼─────────────────▼─────────────────▼───────┐
│                    Apache                          │
│              (Reverse Proxy)                       │
└───────────────────────────────────────────────────┘
```

## Directory Structure

```
/etc/frame/                    # Configuration files
├── frame.conf                 # Main configuration
└── limits.conf                # Default resource limits

/var/frame/                    # Runtime data
├── instances/                 # Per-user instance data
│   └── {username}/
│       ├── apps/              # User's applications
│       ├── logs/              # Application logs
│       └── config/            # User-specific config
└── manager/                   # Manager daemon data

/var/log/frame/                # Log files
├── manager.log                # Manager daemon log
└── {username}/                # Per-user logs

/usr/local/cpanel/
├── base/frontend/jupiter/frame/   # cPanel interface
├── whostmgr/docroot/cgi/frame/    # WHM interface
├── Cpanel/API/Frame.pm            # cPanel UAPI
└── Whostmgr/API/1/Frame.pm        # WHM API
```

## Configuration

### Main Configuration (`/etc/frame/frame.conf`)

```ini
[service]
enabled = true
listen_address = 127.0.0.1
api_port = 9500

[ports]
range_start = 30001
range_end = 32000

[defaults]
memory_limit_mb = 512
max_apps_per_user = 10
auto_start = true

[logging]
level = info
file = /var/log/frame/manager.log
```

### Resource Limits (`/etc/frame/limits.conf`)

```ini
[default]
memory_mb = 512
cpu_percent = 100
max_apps = 10

[premium]
memory_mb = 2048
cpu_percent = 200
max_apps = 50
```

## WHM Administration

Access the Frame Manager in WHM under **Plugins > Frame Manager**.

### Dashboard
- View overall system status
- Monitor active instances
- Start/stop the Frame service

### User Instances
- List all user Frame instances
- Start/stop/restart individual instances
- View per-user resource usage

### Settings
- Configure global defaults
- Set port ranges
- Manage resource limit packages

## cPanel User Interface

Users access Frame Applications in cPanel under **Applications > Frame Applications**.

### Dashboard
- View instance status
- Quick deploy new applications
- Monitor resource usage

### My Apps
- List deployed applications
- Configure domains
- View application logs

### Deploy
- Create new applications
- Upload .cln/.clean files
- Configure initial settings

## API Reference

### WHM API

```perl
# Get service status
my $result = Whostmgr::API::1::Frame::status();

# List all instances
my $result = Whostmgr::API::1::Frame::instances();

# Start user instance
my $result = Whostmgr::API::1::Frame::start_instance({ user => 'username' });
```

### cPanel UAPI

```perl
# Get user's Frame status
my $result = Cpanel::API::Frame::status();

# List user's applications
my $result = Cpanel::API::Frame::list_apps();

# Deploy new application
my $result = Cpanel::API::Frame::deploy_app({ name => 'myapp' });
```

### Manager Daemon API

The Frame manager exposes a REST API on port 9500 (localhost only):

```bash
# Get status
curl http://localhost:9500/api/status

# List instances
curl http://localhost:9500/api/instances

# Start instance
curl -X POST http://localhost:9500/api/instances/username/start
```

## Command Line Tools

### frame-manager

```bash
# Start the manager daemon
frame-manager start

# Manage user instances
frame-manager user start <username>
frame-manager user stop <username>
frame-manager user status <username>

# Port management
frame-manager port list
```

### frame-apache-ctl.sh

```bash
# Initialize Apache configuration
frame-apache-ctl.sh init

# Show status
frame-apache-ctl.sh status

# Reload Apache
frame-apache-ctl.sh reload
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl status frame-manager

# View logs
journalctl -u frame-manager -f
```

### User Instance Issues

```bash
# Check user's instance status
frame-manager user status <username>

# View user's logs
tail -f /var/log/frame/<username>/app.log
```

## Development

### Building from Source

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Build release version
make release

# Run tests
make test
```

### Project Structure

```
clean-cpanel-plugin/
├── src/
│   ├── manager/           # Rust daemon source
│   ├── api/               # API modules (Perl)
│   ├── cpanel/            # cPanel interface
│   ├── whm/               # WHM interface
│   ├── hooks/             # cPanel account hooks
│   └── apache/            # Apache configuration
├── packaging/             # Config and packaging files
├── scripts/               # Installation scripts
└── documents/             # Specifications
```

## Related Projects

- [Clean Language Compiler](../clean-language-compiler) - The Clean Language compiler
- [Frame Framework](../clean-framework) - The Frame full-stack framework
- [Clean Server](../clean-server) - The Frame server runtime

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- Documentation: https://docs.cleanlanguage.dev/cpanel-plugin
- Issues: https://github.com/cleanlanguage/clean-cpanel-plugin/issues
