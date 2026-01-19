# Frame cPanel Plugin Specification

## Overview

The Frame cPanel Plugin enables hosting providers and server administrators to offer Clean Language/Frame application hosting through cPanel/WHM. It registers the Frame server as a managed service and provides user-friendly interfaces for deploying, managing, and monitoring Frame applications.

### Goals

- Enable Frame application hosting on cPanel-managed servers
- Provide per-user application isolation via WASM sandboxing
- Integrate with cPanel's service management infrastructure
- Support both shared hosting and VPS/dedicated environments
- Offer WHM admin controls and cPanel user interfaces
- Zero-configuration deployment for end users

### Non-Goals

- Replacing existing web servers (Apache/NGINX)
- Managing non-Frame applications
- Providing a full IDE (users should use external editors)

---

## Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         WHM Interface                            │
│  (Admin: Global settings, resource limits, service management)   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Frame Service Manager                         │
│         (Daemon management, port allocation, monitoring)         │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              ┌─────────┐ ┌─────────┐ ┌─────────┐
              │ User A  │ │ User B  │ │ User C  │
              │ Instance│ │ Instance│ │ Instance│
              └─────────┘ └─────────┘ └─────────┘
                    │           │           │
                    ▼           ▼           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      cPanel Interface                            │
│    (User: App deployment, logs, environment, domain mapping)     │
└─────────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. Frame Service Manager (Daemon)

The central daemon that orchestrates all Frame instances on the server.

**Responsibilities:**
- Start/stop/restart individual user instances
- Port allocation and management
- Health monitoring and auto-restart
- Resource enforcement (memory, CPU limits)
- Log aggregation and rotation

**Location:** `/usr/local/cpanel/3rdparty/bin/frame-manager`

#### 2. WHM Admin Module

Server-wide administration interface for hosting providers.

**Features:**
- Global Frame service enable/disable
- Default resource limits per package
- Instance overview and management
- Service health dashboard
- License management (if applicable)

**Location:** `/usr/local/cpanel/whostmgr/docroot/cgi/frame/`

#### 3. cPanel User Module

End-user interface for managing their Frame applications.

**Features:**
- Application deployment (upload .cln files or Git deploy)
- Environment variable management
- Domain/subdomain mapping
- Application logs viewer
- Start/stop/restart controls
- Database connection configuration

**Location:** `/usr/local/cpanel/base/frontend/jupiter/frame/`

#### 4. Frame Runtime Binary

The actual Frame server binary that runs user applications.

**Location:** `/usr/local/cpanel/3rdparty/bin/frame-server`

---

## Installation

### Prerequisites

- cPanel/WHM 11.102+ (or later)
- CentOS/AlmaLinux/Rocky Linux 8+ or Ubuntu 22.04+
- Root access
- Minimum 2GB RAM (4GB+ recommended)
- glibc 2.17+

### RPM Installation (Recommended)

```bash
# Add Frame repository
curl -fsSL https://repo.cleanlanguage.io/gpg.key | rpm --import -
cat > /etc/yum.repos.d/frame.repo << 'EOF'
[frame]
name=Frame Repository
baseurl=https://repo.cleanlanguage.io/rpm/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.cleanlanguage.io/gpg.key
EOF

# Install the plugin
yum install frame-cpanel-plugin

# Register with cPanel
/usr/local/cpanel/scripts/install_plugin /usr/local/frame-cpanel/plugin.tar.gz
```

### Manual Installation

```bash
# Download and extract
wget https://releases.cleanlanguage.io/cpanel/frame-cpanel-latest.tar.gz
tar -xzf frame-cpanel-latest.tar.gz -C /usr/local/

# Run installer
/usr/local/frame-cpanel/install.sh

# Verify installation
/usr/local/cpanel/bin/manage_plugins --list | grep frame
```

### Post-Installation

```bash
# Start the Frame service manager
systemctl enable frame-manager
systemctl start frame-manager

# Verify WHM integration
/usr/local/cpanel/bin/whmapi1 listaccts | head
```

---

## Directory Structure

```
/usr/local/cpanel/
├── 3rdparty/
│   └── bin/
│       ├── frame-server          # Frame runtime binary
│       └── frame-manager         # Service manager daemon
├── base/
│   └── frontend/
│       └── jupiter/
│           └── frame/            # cPanel user interface
│               ├── index.live.cgi
│               ├── api.live.cgi
│               ├── assets/
│               └── views/
├── whostmgr/
│   └── docroot/
│       └── cgi/
│           └── frame/            # WHM admin interface
│               ├── index.cgi
│               ├── api.cgi
│               └── templates/
└── scripts/
    └── frame/                    # Hook scripts
        ├── postwwwacct
        ├── prekillacct
        └── postacctremove

/var/frame/
├── instances/                    # Per-user instance data
│   └── {username}/
│       ├── apps/                 # User's Frame applications
│       ├── data/                 # Application data
│       ├── logs/                 # Instance logs
│       └── config.json           # Instance configuration
├── shared/                       # Shared resources
│   └── stdlib/                   # Standard library cache
└── manager/
    ├── state.json                # Service manager state
    └── ports.json                # Port allocation registry

/etc/frame/
├── frame.conf                    # Global configuration
├── limits.conf                   # Resource limits
└── packages/                     # Per-package overrides
    └── {package_name}.conf
```

---

## Service Management

### Systemd Unit: frame-manager

```ini
[Unit]
Description=Frame Service Manager for cPanel
After=network.target cpanel.service
Wants=cpanel.service

[Service]
Type=simple
ExecStart=/usr/local/cpanel/3rdparty/bin/frame-manager
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5
User=root
Group=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

### cPanel Init Script Integration

Register with cPanel's restart system:

```perl
# /var/cpanel/perl/Cpanel/ServiceManager/Services/Frame.pm
package Cpanel::ServiceManager::Services::Frame;

use strict;
use warnings;

sub new { return bless {}, shift }

sub service_name { return 'frame-manager' }

sub is_enabled {
    return -e '/etc/systemd/system/multi-user.target.wants/frame-manager.service';
}

sub _start { system('systemctl start frame-manager') }
sub _stop  { system('systemctl stop frame-manager') }
sub _restart { system('systemctl restart frame-manager') }

1;
```

### Per-User Instance Management

Each cPanel user gets an isolated Frame instance:

```bash
# Start user instance
frame-manager user start <username>

# Stop user instance
frame-manager user stop <username>

# Restart user instance
frame-manager user restart <username>

# View instance status
frame-manager user status <username>
```

---

## Port Allocation

### Strategy

The Frame manager allocates ports dynamically from a configurable range:

```
Default range: 30000-32000
Reserved ports: 30000 (manager API)
User ports: 30001-32000
```

### Port Registry

`/var/frame/manager/ports.json`:

```json
{
  "range": {
    "start": 30001,
    "end": 32000
  },
  "allocated": {
    "user1": 30001,
    "user2": 30002,
    "user3": 30003
  },
  "released": [30004, 30010]
}
```

### Reverse Proxy Integration

Frame instances are proxied through Apache/NGINX:

**Apache (via .htaccess or vhost):**
```apache
# /home/{user}/public_html/.htaccess
RewriteEngine On
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule /frame/(.*) ws://127.0.0.1:{PORT}/\$1 [P,L]
RewriteRule ^frame/(.*) http://127.0.0.1:{PORT}/\$1 [P,L]
```

**NGINX (if using NGINX Manager):**
```nginx
location /frame/ {
    proxy_pass http://127.0.0.1:{PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

---

## User Isolation & Security

### WASM Sandboxing

All Frame applications run in WASM sandboxes with:
- No direct filesystem access (only via Host Bridge)
- No network access except through Host Bridge
- Memory limits enforced by WASM runtime
- CPU time limits via manager

### Linux User Separation

Each instance runs as the cPanel user:

```bash
# Instance process ownership
sudo -u {username} /usr/local/cpanel/3rdparty/bin/frame-server \
  --port {allocated_port} \
  --app-dir /var/frame/instances/{username}/apps \
  --data-dir /var/frame/instances/{username}/data
```

### Resource Limits

Configured per-package in `/etc/frame/packages/{package}.conf`:

```ini
[limits]
# Memory limit per instance (MB)
memory_limit = 512

# CPU percentage limit (0-100)
cpu_limit = 25

# Maximum concurrent connections
max_connections = 100

# Maximum applications per user
max_apps = 5

# Disk quota for Frame data (MB)
disk_quota = 1024
```

### Host Bridge Allowlist

Per-user Host Bridge permissions:

```json
{
  "allowed_namespaces": [
    "bridge:http.fetch",
    "bridge:db.*",
    "bridge:env.get",
    "bridge:time.*",
    "bridge:crypto.*",
    "bridge:log.*"
  ],
  "denied_namespaces": [
    "bridge:fs.*",
    "bridge:sys.*"
  ]
}
```

---

## WHM Interface

### Dashboard (`/cgi/frame/index.cgi`)

```
┌─────────────────────────────────────────────────────────────────┐
│ Frame Server Management                              [Settings] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Service Status: ● Running                    [Restart Service] │
│  Active Instances: 42 / 100                                     │
│  Memory Usage: 8.2 GB / 32 GB                                   │
│  Port Range: 30001 - 32000                                      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Active Instances                                                │
├──────────┬─────────┬────────┬─────────┬────────────────────────┤
│ User     │ Port    │ Memory │ Status  │ Actions                │
├──────────┼─────────┼────────┼─────────┼────────────────────────┤
│ user1    │ 30001   │ 256 MB │ ● Run   │ [Stop] [Restart] [Logs]│
│ user2    │ 30002   │ 128 MB │ ● Run   │ [Stop] [Restart] [Logs]│
│ user3    │ 30003   │ 0 MB   │ ○ Stop  │ [Start] [Logs]         │
└──────────┴─────────┴────────┴─────────┴────────────────────────┘
│                                                                 │
│ [Enable for All Users] [Disable for All Users] [View All Logs] │
└─────────────────────────────────────────────────────────────────┘
```

### Settings Page

- Global enable/disable
- Default resource limits
- Port range configuration
- Auto-start on account creation
- Log retention settings
- Update management

### Package Integration

Add Frame limits to hosting packages:

```
Package: Premium Hosting
├── Disk Space: 10 GB
├── Bandwidth: 100 GB
├── Email Accounts: Unlimited
└── Frame Settings:
    ├── Enabled: Yes
    ├── Memory Limit: 1024 MB
    ├── Max Apps: 10
    └── CPU Limit: 50%
```

---

## cPanel Interface

### Main Dashboard (`/frame/index.live.cgi`)

```
┌─────────────────────────────────────────────────────────────────┐
│ Frame Applications                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Instance Status: ● Running on port 30001                       │
│  Memory: 128 MB / 512 MB                                        │
│  Apps: 2 / 5                                                    │
│                                                                 │
│  [Deploy New App] [View Logs] [Environment Variables]           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Your Applications                                               │
├──────────────────┬─────────────────┬────────────────────────────┤
│ App Name         │ Domain          │ Actions                    │
├──────────────────┼─────────────────┼────────────────────────────┤
│ my-blog          │ blog.domain.com │ [Open] [Settings] [Delete] │
│ api-server       │ api.domain.com  │ [Open] [Settings] [Delete] │
└──────────────────┴─────────────────┴────────────────────────────┘
│                                                                 │
│ Quick Deploy:                                                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ [Upload .cln files] or [Connect Git Repository]            │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Deploy Application Flow

1. **Upload Method:**
   - User uploads `.cln` files via web interface
   - Files validated and compiled
   - Application deployed and started

2. **Git Method:**
   - User provides Git repository URL
   - Plugin clones repository
   - Automatic deployment on push (webhook)

### Application Settings

- Custom domain/subdomain mapping
- Environment variables (encrypted at rest)
- Database connections (MySQL/PostgreSQL)
- SSL certificate selection
- Cache settings
- Error handling preferences

### Logs Viewer

Real-time log streaming with filters:
- Application logs
- Error logs
- Access logs
- Filter by date range
- Search functionality
- Download as file

---

## API Endpoints

### WHM API (Admin)

Base: `https://server:2087/json-api/`

```
GET  /frame/status              # Service status
POST /frame/restart             # Restart service
GET  /frame/instances           # List all instances
POST /frame/instances/{user}/start
POST /frame/instances/{user}/stop
POST /frame/instances/{user}/restart
GET  /frame/instances/{user}/logs
PUT  /frame/settings            # Update global settings
GET  /frame/packages            # List package configs
PUT  /frame/packages/{name}     # Update package config
```

### cPanel API (User)

Base: `https://server:2083/execute/`

```
GET  Frame/status               # User's instance status
POST Frame/start                # Start instance
POST Frame/stop                 # Stop instance
POST Frame/restart              # Restart instance
GET  Frame/apps                 # List applications
POST Frame/apps                 # Deploy new application
DELETE Frame/apps/{name}        # Remove application
PUT  Frame/apps/{name}          # Update application
GET  Frame/apps/{name}/logs     # Application logs
GET  Frame/env                  # List env variables
PUT  Frame/env                  # Set env variables
GET  Frame/domains              # List domain mappings
PUT  Frame/domains              # Update domain mappings
```

### API Response Format

All API responses use the standard envelope:

**Success:**
```json
{
  "status": 1,
  "data": {
    "instance_status": "running",
    "port": 30001,
    "memory_usage": 134217728,
    "apps": [
      {"name": "my-blog", "status": "running"}
    ]
  }
}
```

**Error:**
```json
{
  "status": 0,
  "errors": [
    "Instance not found for user: nonexistent"
  ]
}
```

---

## Hooks & Events

### cPanel Account Hooks

**Post Account Creation (`postwwwacct`):**
```bash
#!/bin/bash
# /usr/local/cpanel/scripts/frame/postwwwacct

USERNAME=$1

# Create user's Frame directory structure
mkdir -p /var/frame/instances/$USERNAME/{apps,data,logs}
chown -R $USERNAME:$USERNAME /var/frame/instances/$USERNAME

# Initialize config
cat > /var/frame/instances/$USERNAME/config.json << EOF
{
  "auto_start": true,
  "memory_limit": 512,
  "max_apps": 5
}
EOF

# Start instance if auto-start enabled
/usr/local/cpanel/3rdparty/bin/frame-manager user start $USERNAME
```

**Pre Account Removal (`prekillacct`):**
```bash
#!/bin/bash
# /usr/local/cpanel/scripts/frame/prekillacct

USERNAME=$1

# Stop user's Frame instance
/usr/local/cpanel/3rdparty/bin/frame-manager user stop $USERNAME

# Release allocated port
/usr/local/cpanel/3rdparty/bin/frame-manager port release $USERNAME
```

**Post Account Removal (`postacctremove`):**
```bash
#!/bin/bash
# /usr/local/cpanel/scripts/frame/postacctremove

USERNAME=$1

# Remove user's Frame data
rm -rf /var/frame/instances/$USERNAME
```

### Custom Event Hooks

Frame manager emits events for external integration:

```json
{
  "event": "instance.started",
  "timestamp": "2026-01-19T10:30:00Z",
  "data": {
    "username": "user1",
    "port": 30001,
    "apps": ["my-blog"]
  }
}
```

Events:
- `instance.started`
- `instance.stopped`
- `instance.crashed`
- `app.deployed`
- `app.removed`
- `resource.limit_reached`

---

## Configuration Reference

### Global Config (`/etc/frame/frame.conf`)

```ini
[service]
# Enable Frame service globally
enabled = true

# Port range for user instances
port_range_start = 30001
port_range_end = 32000

# Manager API port
manager_port = 30000

# Auto-start instances on boot
auto_start = true

# Health check interval (seconds)
health_check_interval = 30

[defaults]
# Default memory limit (MB)
memory_limit = 512

# Default CPU limit (percentage)
cpu_limit = 25

# Default max apps per user
max_apps = 5

# Default disk quota (MB)
disk_quota = 1024

[logging]
# Log level: debug, info, warn, error
level = info

# Log retention (days)
retention_days = 30

# Max log file size (MB)
max_file_size = 100

[security]
# Allow filesystem access via Host Bridge
allow_fs_access = false

# Allow system info access
allow_sys_access = false

# Require HTTPS for external connections
require_https = true

[proxy]
# Proxy backend (apache or nginx)
backend = apache

# Proxy timeout (seconds)
timeout = 60

# Enable WebSocket proxying
websocket = true
```

### Package Override (`/etc/frame/packages/{package}.conf`)

```ini
[limits]
memory_limit = 1024
cpu_limit = 50
max_apps = 10
disk_quota = 2048

[features]
fs_access = false
sys_access = false
custom_domains = true
ssl_support = true
```

---

## Monitoring & Health

### Health Checks

The Frame manager performs periodic health checks:

1. **Process Check:** Verify instance process is running
2. **Port Check:** Verify instance is listening on allocated port
3. **Memory Check:** Verify memory usage within limits
4. **Response Check:** HTTP health endpoint responds

### Metrics Export

Prometheus-compatible metrics at `http://localhost:30000/metrics`:

```
# Instance metrics
frame_instances_total 42
frame_instances_running 40
frame_instances_stopped 2

# Resource metrics
frame_memory_usage_bytes{user="user1"} 134217728
frame_cpu_usage_percent{user="user1"} 15.5

# Request metrics
frame_requests_total{user="user1",app="my-blog"} 15420
frame_request_duration_seconds{user="user1",app="my-blog",quantile="0.99"} 0.045
```

### Alerting

Configure alerts in `/etc/frame/alerts.conf`:

```ini
[alerts]
# Email alerts
email_enabled = true
email_to = admin@example.com

# Alert thresholds
memory_threshold = 90
cpu_threshold = 90
disk_threshold = 85

# Alert on instance crash
alert_on_crash = true

# Alert on resource limit
alert_on_limit = true
```

---

## Upgrade & Maintenance

### Upgrade Process

```bash
# Stop service
systemctl stop frame-manager

# Backup current installation
tar -czf /root/frame-backup-$(date +%Y%m%d).tar.gz \
  /usr/local/cpanel/3rdparty/bin/frame-* \
  /var/frame/

# Upgrade via RPM
yum update frame-cpanel-plugin

# Run migration scripts (if any)
/usr/local/frame-cpanel/scripts/migrate.sh

# Start service
systemctl start frame-manager
```

### Rollback

```bash
# Stop service
systemctl stop frame-manager

# Restore from backup
tar -xzf /root/frame-backup-YYYYMMDD.tar.gz -C /

# Start service
systemctl start frame-manager
```

---

## Troubleshooting

### Common Issues

**Instance won't start:**
```bash
# Check logs
journalctl -u frame-manager -f

# Check user's instance logs
cat /var/frame/instances/{username}/logs/error.log

# Verify port availability
netstat -tlnp | grep {port}
```

**High memory usage:**
```bash
# Check per-instance memory
frame-manager stats memory

# Adjust limits
vi /etc/frame/packages/{package}.conf
frame-manager reload
```

**Proxy not working:**
```bash
# Verify Apache/NGINX config
httpd -t  # or nginx -t

# Check proxy module loaded
httpd -M | grep proxy
```

### Debug Mode

Enable debug logging:

```bash
# In /etc/frame/frame.conf
[logging]
level = debug

# Restart
systemctl restart frame-manager

# View debug logs
journalctl -u frame-manager -f
```

---

## Distribution

### RPM Package Structure

```
frame-cpanel-plugin-1.0.0-1.el8.x86_64.rpm
├── /usr/local/cpanel/3rdparty/bin/
│   ├── frame-server
│   └── frame-manager
├── /usr/local/cpanel/base/frontend/jupiter/frame/
│   └── (cPanel UI files)
├── /usr/local/cpanel/whostmgr/docroot/cgi/frame/
│   └── (WHM UI files)
├── /usr/local/cpanel/scripts/frame/
│   └── (hook scripts)
├── /etc/frame/
│   ├── frame.conf
│   └── limits.conf
├── /usr/lib/systemd/system/
│   └── frame-manager.service
└── /usr/local/frame-cpanel/
    ├── install.sh
    ├── uninstall.sh
    └── plugin.tar.gz
```

### GitHub Repository Structure

```
clean-cpanel-plugin/
├── documents/
│   └── CPANEL_PLUGIN_SPECIFICATION.md  # This file
├── src/
│   ├── manager/                        # Frame manager daemon
│   ├── whm/                            # WHM interface
│   ├── cpanel/                         # cPanel interface
│   ├── hooks/                          # cPanel hooks
│   └── api/                            # API handlers
├── packaging/
│   ├── rpm/                            # RPM spec files
│   └── deb/                            # Debian packages (future)
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── migrate.sh
├── tests/
│   ├── unit/
│   └── integration/
├── CLAUDE.md
├── README.md
├── LICENSE
└── Makefile
```

### License

Recommended: MIT or Apache 2.0 for maximum adoption.

```
MIT License

Copyright (c) 2026 Clean Language Project

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

---

## Roadmap

### Phase 1: Core Functionality
- [ ] Frame manager daemon
- [ ] Basic WHM interface
- [ ] Basic cPanel interface
- [ ] RPM packaging
- [ ] Installation scripts

### Phase 2: User Experience
- [ ] Git deployment integration
- [ ] Real-time log viewer
- [ ] Domain mapping UI
- [ ] Environment variable management

### Phase 3: Advanced Features
- [ ] Prometheus metrics
- [ ] Alert system
- [ ] Auto-scaling (VPS only)
- [ ] Backup/restore functionality

### Phase 4: Enterprise
- [ ] Multi-server clustering
- [ ] Load balancing
- [ ] High availability
- [ ] Commercial licensing option

---

## References

- [cPanel Plugin Development Guide](https://docs.cpanel.net/development/)
- [WHM API Documentation](https://api.docs.cpanel.net/whm/introduction/)
- [cPanel UAPI Documentation](https://api.docs.cpanel.net/cpanel/introduction/)
- [Frame Server Specification](../clean-framework/documents/specification/03_frame_server.md)
- [Host Bridge Contracts](../clean-framework/documents/specification/frame_bridge_contracts.md)
- [Clean Language Specification](../clean-language-compiler/documentation/Clean_Language_Specification.md)
