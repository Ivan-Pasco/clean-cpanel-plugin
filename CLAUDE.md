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

## Cross-Component Work Policy

**CRITICAL: AI Instance Separation of Concerns**

When working in this component and discovering errors, bugs, or required changes in **another component** (different folder in the Clean Language project), you must **NOT** directly fix or modify code in that other component.

Instead:

1. **Document the issue** by creating a prompt/task description
2. **Save the prompt** in a file that can be executed by the AI instance working in the correct folder
3. **Location for cross-component prompts**: Save prompts in `../management/cross-component-prompts/` at the project root

### Prompt Format for Cross-Component Issues

```
Component: [target component name, e.g., clean-language-compiler]
Issue Type: [bug/feature/enhancement/compatibility]
Priority: [critical/high/medium/low]
Description: [Detailed description of the issue discovered]
Context: [Why this was discovered while working in the current component]
Suggested Fix: [If known, describe the potential solution]
Files Affected: [List of files in the target component that need changes]
```

### Why This Rule Exists

- Each component has its own context, dependencies, and testing requirements
- AI instances are optimized for their specific component's codebase
- Cross-component changes without proper context can introduce bugs
- This maintains clear boundaries and accountability
- Ensures changes are properly tested in the target component's environment

### What You CAN Do

- Read files from other components to understand interfaces
- Document compatibility issues found
- Create detailed prompts for the correct AI instance
- Update your component to work with existing interfaces

### What You MUST NOT Do

- Directly edit code in other components
- Make changes to other components' configuration files
- Modify shared resources without coordination
- Skip the prompt creation step for cross-component issues

## Documentation Sync Protocol

Facts about the language live in `spec/` (at the project root). Facts about the platform live in `platform-architecture/`. Do not duplicate them here — link to them instead.

**When you make a change in this component, update the corresponding spec file in the same commit:**

| Change type | Update required |
|-------------|-----------------|
| New or changed host bridge function | `platform-architecture/HOST_BRIDGE.md` |
| New or changed execution layer | `platform-architecture/EXECUTION_LAYERS.md` |

The cPanel plugin orchestrates deployment of Clean Language applications — it does not define language rules or host bridge contracts. When changes here affect platform integration, update the platform-architecture documentation accordingly.

The spec files are the single source of truth. Component documentation explains implementation — it does not redefine language rules.
