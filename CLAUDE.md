# CLAUDE.md - Frame cPanel Plugin Development Guide

This file provides guidance when working with the Frame cPanel Plugin codebase.

## Project Overview

The Frame cPanel Plugin enables hosting providers to offer Clean Language/Frame application hosting through cPanel/WHM. It registers the Frame server as a managed service and provides user-friendly interfaces for deployment and management.

## Key Documents

- **[CPANEL_PLUGIN_SPECIFICATION.md](documents/CPANEL_PLUGIN_SPECIFICATION.md)** - Complete technical specification (START HERE)

## Architecture Summary

```
WHM Interface → Frame Manager Daemon → Per-User Frame Instances → cPanel Interface
```

### Core Components

1. **Frame Manager Daemon** (`src/manager/`) - Central service orchestrator
2. **WHM Module** (`src/whm/`) - Admin interface for hosting providers
3. **cPanel Module** (`src/cpanel/`) - End-user interface
4. **Account Hooks** (`src/hooks/`) - cPanel lifecycle integration
5. **API Handlers** (`src/api/`) - WHM/UAPI endpoints

## Development Rules

### Code Quality Standards

1. **NO PLACEHOLDER IMPLEMENTATIONS**: All code must be fully functional
2. **WORKING CODE ONLY**: Production-ready implementations only
3. **FOLLOW SPECIFICATION**: Always reference the spec document

### Technology Stack

- **Manager Daemon**: Rust (matches Frame server)
- **WHM Interface**: Perl (cPanel standard) + Template Toolkit
- **cPanel Interface**: Perl CGI + JavaScript
- **API Layer**: Perl (WHM API) + cPanel UAPI

### File Naming Conventions

- Perl modules: `PascalCase.pm`
- CGI scripts: `lowercase.cgi` or `lowercase.live.cgi`
- Templates: `lowercase.tmpl`
- Rust files: `snake_case.rs`

## Common Commands

```bash
# Build the manager daemon
cd src/manager && cargo build --release

# Run tests
cargo test

# Build RPM package
make rpm

# Install locally for testing
./scripts/install.sh --dev

# Uninstall
./scripts/uninstall.sh
```

## cPanel Development Notes

### WHM API Integration

```perl
# Register API function
package Whostmgr::API::1::Frame;

sub status {
    my ($args) = @_;
    return { status => 'running', instances => 42 };
}
```

### cPanel UAPI Integration

```perl
# Register UAPI function
package Cpanel::API::Frame;

sub status {
    my ($args, $result) = @_;
    $result->data({ status => 'running' });
    return 1;
}
```

### Hook Scripts

Located in `/usr/local/cpanel/scripts/frame/`:
- `postwwwacct` - After account creation
- `prekillacct` - Before account removal
- `postacctremove` - After account removal

## Testing Strategy

1. **Unit Tests**: Test individual components
2. **Integration Tests**: Test cPanel/WHM integration
3. **E2E Tests**: Full deployment workflow

### Testing Environment

Use cPanel's development VM or Docker container:
```bash
# cPanel trial license for development
curl -o latest -L https://securedownloads.cpanel.net/latest
sh latest
```

## Security Considerations

- All user data in `/var/frame/instances/{user}/` owned by that user
- Frame instances run as the cPanel user, not root
- Host Bridge enforces namespace allowlists
- No direct filesystem/system access from WASM

## Related Projects

- [Frame Framework](../clean-framework/) - Server runtime specification
- [Clean Server](../clean-server/) - Actual server implementation
- [Clean Language Compiler](../clean-language-compiler/) - Compiler

## References

- [cPanel Developer Docs](https://docs.cpanel.net/development/)
- [WHM API Reference](https://api.docs.cpanel.net/whm/introduction/)
- [cPanel UAPI Reference](https://api.docs.cpanel.net/cpanel/introduction/)
