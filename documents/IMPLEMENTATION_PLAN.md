# Frame cPanel Plugin Implementation Plan

## Executive Summary

This document outlines the complete implementation plan for the Frame cPanel Plugin. The project enables hosting providers to offer Clean Language/Frame application hosting through cPanel/WHM. The implementation follows a phased approach aligned with the specification's roadmap.

---

## Current State Analysis

### What Exists
- Complete specification document (1000+ lines)
- Directory skeleton structure
- README and CLAUDE.md documentation

### What Needs to Be Built
- Frame Manager Daemon (Rust)
- WHM Admin Interface (Perl + Template Toolkit)
- cPanel User Interface (Perl CGI + JavaScript)
- API Handlers (Perl)
- Account Hooks (Bash)
- Build System (Makefile, Cargo)
- Packaging (RPM/Deb)
- Installation Scripts
- Test Suite

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Manager Daemon | Rust | Matches Frame server, performance, safety |
| WHM Interface | Perl + Template Toolkit | cPanel standard |
| cPanel Interface | Perl CGI + JavaScript | cPanel standard, modern UX |
| API Layer | Perl (WHM API / UAPI) | cPanel integration |
| Hook Scripts | Bash | Simple, reliable |
| Packaging | RPM (primary), Deb (future) | cPanel server standards |

---

## Phase 1: Core Infrastructure (Foundation)

### 1.1 Build System Setup

**Files to Create:**

```
Cargo.toml                     # Rust workspace manifest
Makefile                       # Main build automation
src/manager/Cargo.toml         # Manager daemon crate
```

**Tasks:**
- [ ] Create Rust workspace configuration
- [ ] Create Makefile with targets: build, test, install, clean, rpm
- [ ] Set up CI/CD configuration (.github/workflows/)

---

### 1.2 Frame Manager Daemon (Rust)

**Location:** `src/manager/`

**Structure:**
```
src/manager/
├── Cargo.toml
├── src/
│   ├── main.rs              # Entry point, CLI parsing
│   ├── lib.rs               # Library root
│   ├── config/
│   │   ├── mod.rs           # Configuration management
│   │   └── parser.rs        # INI file parsing
│   ├── instance/
│   │   ├── mod.rs           # Instance management
│   │   ├── process.rs       # Process spawning/monitoring
│   │   └── resource.rs      # Resource limit enforcement
│   ├── port/
│   │   ├── mod.rs           # Port allocation
│   │   └── registry.rs      # Port registry persistence
│   ├── health/
│   │   ├── mod.rs           # Health check orchestration
│   │   └── checks.rs        # Individual health checks
│   ├── api/
│   │   ├── mod.rs           # HTTP API server
│   │   ├── routes.rs        # API route definitions
│   │   └── handlers.rs      # Request handlers
│   ├── metrics/
│   │   ├── mod.rs           # Metrics collection
│   │   └── prometheus.rs    # Prometheus format export
│   └── events/
│       ├── mod.rs           # Event system
│       └── hooks.rs         # Event hook execution
```

**Core Features:**
1. **Process Management**
   - Start/stop/restart user instances
   - Run instances as cPanel user (sudo -u)
   - Monitor process health
   - Auto-restart on crash

2. **Port Allocation**
   - Dynamic port assignment from range 30001-32000
   - Persistent registry (`/var/frame/manager/ports.json`)
   - Port release on account removal

3. **Resource Enforcement**
   - Memory limits via cgroups v2
   - CPU limits via cgroups
   - Connection limits
   - Disk quota checks

4. **Health Monitoring**
   - Periodic health checks (default: 30s)
   - Process liveness
   - Port binding verification
   - HTTP endpoint response

5. **HTTP API Server**
   - Internal API on port 30000
   - JSON responses
   - Authentication via Unix socket or token

6. **Metrics Export**
   - Prometheus-compatible `/metrics` endpoint
   - Per-instance metrics
   - Aggregate service metrics

**Dependencies (Cargo.toml):**
```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
axum = "0.7"
clap = { version = "4", features = ["derive"] }
tracing = "0.1"
tracing-subscriber = "0.3"
nix = "0.27"
```

---

### 1.3 Configuration System

**Files to Create:**
```
/etc/frame/frame.conf          # Global configuration
/etc/frame/limits.conf         # Default resource limits
/etc/frame/packages/           # Per-package overrides
```

**Implementation:**
- INI file parsing
- Hot reload on SIGHUP
- Validation with sensible defaults
- Package-specific overrides

---

### 1.4 Systemd Integration

**Files to Create:**
```
packaging/systemd/frame-manager.service
```

**Features:**
- Proper dependency ordering (after network, cpanel)
- Automatic restart on failure
- File descriptor limits
- Logging to journald

---

## Phase 2: WHM Interface

### 2.1 WHM API Handlers

**Location:** `src/api/whm/`

**Structure:**
```
src/api/whm/
├── Frame.pm                   # Main API module
├── Frame/
│   ├── Status.pm              # Service status
│   ├── Instances.pm           # Instance management
│   ├── Settings.pm            # Global settings
│   └── Packages.pm            # Package configuration
```

**API Endpoints:**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/frame/status` | GET | Service status |
| `/frame/restart` | POST | Restart service |
| `/frame/instances` | GET | List all instances |
| `/frame/instances/{user}/start` | POST | Start user instance |
| `/frame/instances/{user}/stop` | POST | Stop user instance |
| `/frame/instances/{user}/restart` | POST | Restart user instance |
| `/frame/instances/{user}/logs` | GET | Get instance logs |
| `/frame/settings` | GET/PUT | Global settings |
| `/frame/packages` | GET | List packages |
| `/frame/packages/{name}` | PUT | Update package config |

---

### 2.2 WHM Web Interface

**Location:** `src/whm/`

**Structure:**
```
src/whm/
├── index.cgi                  # Main dashboard
├── api.cgi                    # API proxy
├── lib/
│   └── FrameWHM.pm            # Shared utilities
├── templates/
│   ├── index.tmpl             # Dashboard template
│   ├── settings.tmpl          # Settings page
│   ├── instances.tmpl         # Instance list
│   └── logs.tmpl              # Log viewer
└── assets/
    ├── css/
    │   └── frame.css          # Custom styles
    └── js/
        └── frame.js           # Dashboard JavaScript
```

**Pages:**
1. **Dashboard** - Service status, active instances summary
2. **Instances** - Full instance table with controls
3. **Settings** - Global configuration editor
4. **Logs** - Service and instance log viewer

---

## Phase 3: cPanel Interface

### 3.1 cPanel UAPI Handlers

**Location:** `src/api/cpanel/`

**Structure:**
```
src/api/cpanel/
└── Frame.pm                   # UAPI module
```

**API Functions:**
| Function | Description |
|----------|-------------|
| `status` | User's instance status |
| `start` | Start user instance |
| `stop` | Stop user instance |
| `restart` | Restart user instance |
| `list_apps` | List user's applications |
| `deploy_app` | Deploy new application |
| `remove_app` | Remove application |
| `update_app` | Update application settings |
| `get_logs` | Get application logs |
| `get_env` | Get environment variables |
| `set_env` | Set environment variables |
| `get_domains` | Get domain mappings |
| `set_domains` | Set domain mappings |

---

### 3.2 cPanel Web Interface

**Location:** `src/cpanel/`

**Structure:**
```
src/cpanel/
├── index.live.cgi             # Main dashboard
├── api.live.cgi               # API proxy
├── deploy.live.cgi            # Deployment handler
├── lib/
│   └── FrameCpanel.pm         # Shared utilities
├── views/
│   ├── dashboard.tt           # Main dashboard
│   ├── apps.tt                # Application list
│   ├── deploy.tt              # Deploy form
│   ├── settings.tt            # App settings
│   └── logs.tt                # Log viewer
└── assets/
    ├── css/
    │   └── frame.css          # Custom styles
    └── js/
        ├── frame.js           # Main JavaScript
        ├── deploy.js          # Deployment logic
        └── logs.js            # Real-time log viewer
```

**Pages:**
1. **Dashboard** - Instance status, app list, quick actions
2. **Deploy** - File upload or Git repository input
3. **App Settings** - Domain, environment, database config
4. **Logs** - Real-time log streaming with filters

---

## Phase 4: Account Hooks

**Location:** `src/hooks/`

**Files:**
```
src/hooks/
├── postwwwacct                # After account creation
├── prekillacct                # Before account removal
└── postacctremove             # After account removal
```

### 4.1 postwwwacct (Account Created)

```bash
#!/bin/bash
# Create user's Frame directory structure
# Initialize configuration
# Allocate port
# Start instance if auto_start enabled
```

### 4.2 prekillacct (Before Removal)

```bash
#!/bin/bash
# Stop user's Frame instance
# Release allocated port
# (Data cleanup happens in postacctremove)
```

### 4.3 postacctremove (After Removal)

```bash
#!/bin/bash
# Remove user's Frame directory
# Clean up any orphaned resources
```

---

## Phase 5: Packaging & Distribution

### 5.1 RPM Package

**Location:** `packaging/rpm/`

**Files:**
```
packaging/rpm/
├── frame-cpanel-plugin.spec   # RPM spec file
└── sources/                   # Additional sources
```

**Package Contents:**
- Binaries: frame-manager, frame-server (if bundled)
- WHM interface files
- cPanel interface files
- Hook scripts
- Systemd unit file
- Default configuration files
- Installation scripts

### 5.2 Installation Scripts

**Location:** `scripts/`

**Files:**
```
scripts/
├── install.sh                 # Main installer
├── uninstall.sh               # Complete removal
├── migrate.sh                 # Version migration
└── register-hooks.sh          # cPanel hook registration
```

---

## Phase 6: Testing

### 6.1 Unit Tests

**Location:** `tests/unit/`

**Coverage:**
- Configuration parsing
- Port allocation logic
- Resource limit calculations
- API response formatting

### 6.2 Integration Tests

**Location:** `tests/integration/`

**Coverage:**
- Full instance lifecycle (create, start, stop, remove)
- API endpoint functionality
- Hook script execution
- Package installation/uninstallation

### 6.3 E2E Tests

**Test Scenarios:**
1. Fresh installation on clean cPanel server
2. Account creation with Frame provisioning
3. Application deployment via upload
4. Application deployment via Git
5. Domain mapping configuration
6. Account removal with cleanup

---

## Implementation Order (Recommended)

### Sprint 1: Foundation (Week 1-2)
1. Build system setup (Makefile, Cargo.toml)
2. Frame manager daemon - core structure
3. Configuration system
4. Port allocation
5. Basic process management (start/stop)

### Sprint 2: Manager Completion (Week 3-4)
1. Health monitoring
2. Resource enforcement
3. Internal HTTP API
4. Metrics export
5. Logging system

### Sprint 3: WHM Interface (Week 5-6)
1. WHM API handlers
2. Dashboard page
3. Instance management page
4. Settings page
5. Log viewer

### Sprint 4: cPanel Interface (Week 7-8)
1. cPanel UAPI handlers
2. Dashboard page
3. Application deployment
4. Settings management
5. Log viewer (real-time)

### Sprint 5: Hooks & Integration (Week 9)
1. Account hook scripts
2. Reverse proxy configuration
3. cPanel service registration
4. Integration testing

### Sprint 6: Packaging & Release (Week 10)
1. RPM packaging
2. Installation scripts
3. Documentation
4. Release preparation

---

## File Inventory (Complete List)

### New Files to Create

**Build System:**
- `/Cargo.toml`
- `/Makefile`
- `/.github/workflows/ci.yml`

**Manager Daemon (Rust):**
- `/src/manager/Cargo.toml`
- `/src/manager/src/main.rs`
- `/src/manager/src/lib.rs`
- `/src/manager/src/config/mod.rs`
- `/src/manager/src/config/parser.rs`
- `/src/manager/src/instance/mod.rs`
- `/src/manager/src/instance/process.rs`
- `/src/manager/src/instance/resource.rs`
- `/src/manager/src/port/mod.rs`
- `/src/manager/src/port/registry.rs`
- `/src/manager/src/health/mod.rs`
- `/src/manager/src/health/checks.rs`
- `/src/manager/src/api/mod.rs`
- `/src/manager/src/api/routes.rs`
- `/src/manager/src/api/handlers.rs`
- `/src/manager/src/metrics/mod.rs`
- `/src/manager/src/metrics/prometheus.rs`
- `/src/manager/src/events/mod.rs`
- `/src/manager/src/events/hooks.rs`

**WHM Interface:**
- `/src/whm/index.cgi`
- `/src/whm/api.cgi`
- `/src/whm/lib/FrameWHM.pm`
- `/src/whm/templates/index.tmpl`
- `/src/whm/templates/settings.tmpl`
- `/src/whm/templates/instances.tmpl`
- `/src/whm/templates/logs.tmpl`
- `/src/whm/assets/css/frame.css`
- `/src/whm/assets/js/frame.js`

**WHM API:**
- `/src/api/whm/Frame.pm`
- `/src/api/whm/Frame/Status.pm`
- `/src/api/whm/Frame/Instances.pm`
- `/src/api/whm/Frame/Settings.pm`
- `/src/api/whm/Frame/Packages.pm`

**cPanel Interface:**
- `/src/cpanel/index.live.cgi`
- `/src/cpanel/api.live.cgi`
- `/src/cpanel/deploy.live.cgi`
- `/src/cpanel/lib/FrameCpanel.pm`
- `/src/cpanel/views/dashboard.tt`
- `/src/cpanel/views/apps.tt`
- `/src/cpanel/views/deploy.tt`
- `/src/cpanel/views/settings.tt`
- `/src/cpanel/views/logs.tt`
- `/src/cpanel/assets/css/frame.css`
- `/src/cpanel/assets/js/frame.js`
- `/src/cpanel/assets/js/deploy.js`
- `/src/cpanel/assets/js/logs.js`

**cPanel API:**
- `/src/api/cpanel/Frame.pm`

**Hooks:**
- `/src/hooks/postwwwacct`
- `/src/hooks/prekillacct`
- `/src/hooks/postacctremove`

**Packaging:**
- `/packaging/rpm/frame-cpanel-plugin.spec`
- `/packaging/systemd/frame-manager.service`

**Scripts:**
- `/scripts/install.sh`
- `/scripts/uninstall.sh`
- `/scripts/migrate.sh`
- `/scripts/register-hooks.sh`

**Configuration Templates:**
- `/packaging/config/frame.conf`
- `/packaging/config/limits.conf`

**Tests:**
- `/tests/unit/config_test.rs`
- `/tests/unit/port_test.rs`
- `/tests/integration/lifecycle_test.sh`
- `/tests/integration/api_test.sh`

---

## Risk Assessment

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| cPanel API changes | High | Pin cPanel version, test on multiple versions |
| Resource isolation failures | High | Thorough cgroup testing, fallback limits |
| Port conflicts | Medium | Robust port scanning, retry logic |
| Upgrade failures | Medium | Comprehensive migration scripts, backups |

### Operational Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Server resource exhaustion | High | Hard limits, monitoring alerts |
| Instance crashes affecting others | Medium | Process isolation, watchdog |
| Log storage overflow | Low | Log rotation, retention policies |

---

## Success Criteria

### Phase 1 Complete When:
- [ ] Manager daemon starts and accepts commands
- [ ] Can start/stop Frame instances
- [ ] Port allocation persists across restarts
- [ ] Basic health monitoring works

### Phase 2 Complete When:
- [ ] WHM dashboard shows service status
- [ ] Can manage instances from WHM
- [ ] Settings can be modified

### Phase 3 Complete When:
- [ ] cPanel users can see their instance status
- [ ] Application deployment works (upload)
- [ ] Logs are viewable

### Phase 4 Complete When:
- [ ] New accounts get Frame directories
- [ ] Removed accounts clean up properly
- [ ] Ports are correctly allocated/released

### Phase 5 Complete When:
- [ ] RPM package builds successfully
- [ ] Installation works on fresh cPanel server
- [ ] Uninstallation is clean

---

## Next Steps

1. **Approve this plan** - Review and confirm implementation approach
2. **Set up build system** - Create Cargo.toml and Makefile
3. **Begin Sprint 1** - Start with frame-manager daemon foundation

---

## Appendix A: cPanel Development Resources

- [cPanel Plugin Development](https://docs.cpanel.net/development/)
- [WHM API Reference](https://api.docs.cpanel.net/whm/introduction/)
- [cPanel UAPI Reference](https://api.docs.cpanel.net/cpanel/introduction/)
- [cPanel Hook System](https://docs.cpanel.net/development/hooks-system/)

## Appendix B: Related Clean Language Projects

- [Clean Language Compiler](../clean-language-compiler/)
- [Frame Framework](../clean-framework/)
- [Clean Server](../clean-server/)
