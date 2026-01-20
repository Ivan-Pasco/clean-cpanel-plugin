#!/bin/bash
# Frame Applications - Apache Control Script
# Manages Apache configuration for Frame applications
#
# Usage: frame-apache-ctl.sh <command> [options]

set -e

FRAME_CONF_DIR="/etc/apache2/conf.d/frame"
FRAME_MAIN_CONF="/etc/apache2/conf.d/frame.conf"
FRAME_ERROR_PAGES="/var/www/frame-error"
TEMPLATE_SOURCE="/usr/local/cpanel/whostmgr/docroot/cgi/frame/templates/apache"
ERROR_PAGE_SOURCE="/usr/local/cpanel/whostmgr/docroot/cgi/frame/error-pages"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialize Frame Apache configuration
init() {
    log_info "Initializing Frame Apache configuration..."

    # Create directories
    mkdir -p "$FRAME_CONF_DIR"
    mkdir -p "$FRAME_CONF_DIR/domains"
    mkdir -p "$FRAME_ERROR_PAGES"

    # Copy main configuration
    if [ -f "$TEMPLATE_SOURCE/../frame.conf" ]; then
        cp "$TEMPLATE_SOURCE/../frame.conf" "$FRAME_MAIN_CONF"
        log_info "Installed main configuration: $FRAME_MAIN_CONF"
    fi

    # Copy error pages (if source exists)
    if [ -d "$ERROR_PAGE_SOURCE" ] && ls "$ERROR_PAGE_SOURCE"/*.html &>/dev/null; then
        cp "$ERROR_PAGE_SOURCE"/*.html "$FRAME_ERROR_PAGES/" 2>/dev/null || true
        log_info "Installed error pages to: $FRAME_ERROR_PAGES"
    else
        log_warn "Error pages source not found, skipping (installed by main installer)"
    fi

    # Create include in Apache configuration if not exists
    local include_conf="/etc/apache2/conf.d/includes/pre_virtualhost_global.conf"
    if [ -f "$include_conf" ]; then
        if ! grep -q "frame.conf" "$include_conf"; then
            echo "Include $FRAME_MAIN_CONF" >> "$include_conf"
            log_info "Added Frame include to $include_conf"
        fi
    fi

    # Test and reload Apache
    test_config
    reload

    log_info "Frame Apache configuration initialized successfully"
}

# Remove Frame Apache configuration
cleanup() {
    log_warn "Removing Frame Apache configuration..."

    # Remove Frame configurations
    if [ -d "$FRAME_CONF_DIR" ]; then
        rm -rf "$FRAME_CONF_DIR"
        log_info "Removed: $FRAME_CONF_DIR"
    fi

    if [ -f "$FRAME_MAIN_CONF" ]; then
        rm -f "$FRAME_MAIN_CONF"
        log_info "Removed: $FRAME_MAIN_CONF"
    fi

    if [ -d "$FRAME_ERROR_PAGES" ]; then
        rm -rf "$FRAME_ERROR_PAGES"
        log_info "Removed: $FRAME_ERROR_PAGES"
    fi

    # Remove include from Apache configuration
    local include_conf="/etc/apache2/conf.d/includes/pre_virtualhost_global.conf"
    if [ -f "$include_conf" ]; then
        sed -i '/frame\.conf/d' "$include_conf"
        log_info "Removed Frame include from $include_conf"
    fi

    reload

    log_info "Frame Apache configuration removed"
}

# Test Apache configuration
test_config() {
    log_info "Testing Apache configuration..."
    if apachectl configtest 2>&1; then
        log_info "Apache configuration test passed"
        return 0
    else
        log_error "Apache configuration test failed"
        return 1
    fi
}

# Reload Apache
reload() {
    log_info "Reloading Apache..."
    if apachectl graceful; then
        log_info "Apache reloaded successfully"
    else
        log_error "Failed to reload Apache"
        return 1
    fi
}

# List all Frame configurations
list() {
    log_info "Frame Apache configurations:"
    echo ""

    if [ -d "$FRAME_CONF_DIR/domains" ]; then
        echo "Domain configurations:"
        ls -la "$FRAME_CONF_DIR/domains/"*.conf 2>/dev/null || echo "  (none)"
        echo ""
    fi

    echo "User configurations:"
    for user_dir in "$FRAME_CONF_DIR"/*/; do
        if [ -d "$user_dir" ] && [ "$(basename "$user_dir")" != "domains" ]; then
            echo "  $(basename "$user_dir"):"
            ls "$user_dir"*.conf 2>/dev/null | while read -r conf; do
                echo "    - $(basename "$conf")"
            done
        fi
    done
}

# Show status
status() {
    echo "Frame Apache Configuration Status"
    echo "=================================="
    echo ""

    echo "Main configuration: $FRAME_MAIN_CONF"
    if [ -f "$FRAME_MAIN_CONF" ]; then
        echo "  Status: Installed"
    else
        echo "  Status: Not installed"
    fi
    echo ""

    echo "Configuration directory: $FRAME_CONF_DIR"
    if [ -d "$FRAME_CONF_DIR" ]; then
        local domain_count=$(ls "$FRAME_CONF_DIR/domains/"*.conf 2>/dev/null | wc -l)
        echo "  Domain configs: $domain_count"

        local user_count=0
        for user_dir in "$FRAME_CONF_DIR"/*/; do
            if [ -d "$user_dir" ] && [ "$(basename "$user_dir")" != "domains" ]; then
                ((user_count++))
            fi
        done
        echo "  User directories: $user_count"
    else
        echo "  Status: Not initialized"
    fi
    echo ""

    echo "Error pages: $FRAME_ERROR_PAGES"
    if [ -d "$FRAME_ERROR_PAGES" ]; then
        echo "  Status: Installed"
    else
        echo "  Status: Not installed"
    fi
    echo ""

    # Check if Frame module is loaded in Apache
    if apachectl -M 2>/dev/null | grep -q "proxy_module"; then
        echo "Apache proxy_module: Loaded"
    else
        echo "Apache proxy_module: Not loaded"
    fi
}

# Show usage
usage() {
    cat <<EOF
Frame Apache Control Script

Usage: $0 <command>

Commands:
  init      Initialize Frame Apache configuration
  cleanup   Remove all Frame Apache configuration
  test      Test Apache configuration
  reload    Reload Apache
  list      List all Frame configurations
  status    Show configuration status
  help      Show this help message

Examples:
  $0 init      # Set up Frame Apache configuration
  $0 status    # Check current status
  $0 reload    # Reload Apache after manual changes

EOF
}

# Main
case "${1:-}" in
    init)
        init
        ;;
    cleanup)
        cleanup
        ;;
    test)
        test_config
        ;;
    reload)
        reload
        ;;
    list)
        list
        ;;
    status)
        status
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
