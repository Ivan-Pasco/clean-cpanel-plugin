#!/bin/bash
# Frame cPanel Plugin - Installation Script
# Installs all components of the Frame cPanel plugin
#
# Usage: ./install.sh [--dev]

set -e

# Configuration
FRAME_VERSION="1.0.0"
CPANEL_BASE="/usr/local/cpanel"
WHM_DOCROOT="$CPANEL_BASE/whostmgr/docroot"
CPANEL_FRONTEND="$CPANEL_BASE/base/frontend/jupiter"
FRAME_VAR="/var/frame"
FRAME_LOG="/var/log/frame"
FRAME_ETC="/etc/frame"
APACHE_CONF="/etc/apache2/conf.d"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check for cPanel
check_cpanel() {
    if [ ! -d "$CPANEL_BASE" ]; then
        log_error "cPanel not found at $CPANEL_BASE"
        exit 1
    fi

    if [ ! -f "$CPANEL_BASE/version" ]; then
        log_warn "Cannot determine cPanel version"
    else
        local version=$(cat "$CPANEL_BASE/version")
        log_info "Detected cPanel version: $version"
    fi
}

# Check dependencies
check_dependencies() {
    log_step "Checking dependencies..."

    # Check for required Perl modules
    local missing_modules=()

    for module in "Template" "JSON" "CGI" "DBI"; do
        if ! perl -M$module -e 1 2>/dev/null; then
            missing_modules+=("$module")
        fi
    done

    if [ ${#missing_modules[@]} -gt 0 ]; then
        log_warn "Missing Perl modules: ${missing_modules[*]}"
        log_info "Installing missing modules..."
        for module in "${missing_modules[@]}"; do
            cpan -i "$module" || true
        done
    fi

    # Check for systemd
    if ! command -v systemctl &>/dev/null; then
        log_error "systemd is required but not found"
        exit 1
    fi

    log_info "Dependencies check passed"
}

# Create directories
create_directories() {
    log_step "Creating directories..."

    # Frame data directories
    mkdir -p "$FRAME_VAR"
    mkdir -p "$FRAME_VAR/instances"
    mkdir -p "$FRAME_LOG"
    mkdir -p "$FRAME_ETC"

    # Apache directories
    mkdir -p "$APACHE_CONF/frame"
    mkdir -p "$APACHE_CONF/frame/domains"
    mkdir -p "/var/www/frame-error"

    # cPanel directories
    mkdir -p "$CPANEL_FRONTEND/frame/views"
    mkdir -p "$CPANEL_FRONTEND/frame/assets/css"
    mkdir -p "$CPANEL_FRONTEND/frame/assets/js"
    mkdir -p "$CPANEL_FRONTEND/frame/lib"

    # WHM directories
    mkdir -p "$WHM_DOCROOT/cgi/frame/templates"
    mkdir -p "$WHM_DOCROOT/cgi/frame/templates/apache"
    mkdir -p "$WHM_DOCROOT/cgi/frame/assets/css"
    mkdir -p "$WHM_DOCROOT/cgi/frame/assets/js"
    mkdir -p "$WHM_DOCROOT/cgi/frame/lib"
    mkdir -p "$WHM_DOCROOT/cgi/frame/error-pages"

    # Hook directories
    mkdir -p "$CPANEL_BASE/scripts/postwwwacct"
    mkdir -p "$CPANEL_BASE/scripts/prekillacct"
    mkdir -p "$CPANEL_BASE/scripts/postacctremove"

    # Set permissions
    chmod 755 "$FRAME_VAR"
    chmod 755 "$FRAME_VAR/instances"
    chmod 755 "$FRAME_LOG"
    chmod 755 "$FRAME_ETC"

    log_info "Directories created"
}

# Install Frame manager daemon
install_daemon() {
    log_step "Installing Frame manager daemon..."

    local binary=""

    # Check multiple locations for the binary
    # 1. Pre-built binary in project root (from GitHub release)
    # 2. Built binary in target/release (workspace build)
    # 3. Built binary in src/manager/target/release (direct build)

    if [ -f "$PROJECT_DIR/frame-manager" ]; then
        binary="$PROJECT_DIR/frame-manager"
        log_info "Using pre-built binary from release package"
    elif [ -f "$PROJECT_DIR/target/release/frame-manager" ]; then
        binary="$PROJECT_DIR/target/release/frame-manager"
        log_info "Using binary from workspace build"
    elif [ -f "$PROJECT_DIR/src/manager/target/release/frame-manager" ]; then
        binary="$PROJECT_DIR/src/manager/target/release/frame-manager"
        log_info "Using binary from direct build"
    fi

    if [ -z "$binary" ] || [ ! -f "$binary" ]; then
        # Try to build if cargo is available
        if command -v cargo &>/dev/null; then
            log_warn "Binary not found, attempting to build..."
            cd "$PROJECT_DIR"
            cargo build --release -p frame-manager
            binary="$PROJECT_DIR/target/release/frame-manager"
        else
            log_error "frame-manager binary not found and cargo is not available"
            log_error "Please download a pre-built release from GitHub"
            exit 1
        fi
    fi

    if [ -f "$binary" ]; then
        cp "$binary" /usr/local/bin/frame-manager
        chmod 755 /usr/local/bin/frame-manager
        log_info "Installed: /usr/local/bin/frame-manager"
    else
        log_error "Failed to find or build frame-manager binary"
        exit 1
    fi
}

# Install systemd service
install_systemd() {
    log_step "Installing systemd service..."

    cp "$PROJECT_DIR/packaging/systemd/frame-manager.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable frame-manager

    log_info "Installed: /etc/systemd/system/frame-manager.service"
}

# Install configuration files
install_config() {
    log_step "Installing configuration files..."

    # Only install if not exists (preserve user settings)
    if [ ! -f "$FRAME_ETC/frame.conf" ]; then
        cp "$PROJECT_DIR/packaging/config/frame.conf" "$FRAME_ETC/"
        log_info "Installed: $FRAME_ETC/frame.conf"
    else
        log_warn "Configuration exists, skipping: $FRAME_ETC/frame.conf"
    fi

    if [ ! -f "$FRAME_ETC/limits.conf" ]; then
        cp "$PROJECT_DIR/packaging/config/limits.conf" "$FRAME_ETC/"
        log_info "Installed: $FRAME_ETC/limits.conf"
    else
        log_warn "Configuration exists, skipping: $FRAME_ETC/limits.conf"
    fi
}

# Install cPanel hooks
install_hooks() {
    log_step "Installing cPanel hooks..."

    cp "$PROJECT_DIR/src/hooks/postwwwacct" "$CPANEL_BASE/scripts/postwwwacct/frame"
    cp "$PROJECT_DIR/src/hooks/prekillacct" "$CPANEL_BASE/scripts/prekillacct/frame"
    cp "$PROJECT_DIR/src/hooks/postacctremove" "$CPANEL_BASE/scripts/postacctremove/frame"

    chmod 755 "$CPANEL_BASE/scripts/postwwwacct/frame"
    chmod 755 "$CPANEL_BASE/scripts/prekillacct/frame"
    chmod 755 "$CPANEL_BASE/scripts/postacctremove/frame"

    log_info "Installed cPanel account hooks"
}

# Install WHM interface
install_whm() {
    log_step "Installing WHM interface..."

    # CGI scripts
    cp "$PROJECT_DIR/src/whm/index.cgi" "$WHM_DOCROOT/cgi/frame/"
    cp "$PROJECT_DIR/src/whm/api.cgi" "$WHM_DOCROOT/cgi/frame/"
    chmod 755 "$WHM_DOCROOT/cgi/frame/"*.cgi

    # Library
    cp "$PROJECT_DIR/src/whm/lib/FrameWHM.pm" "$WHM_DOCROOT/cgi/frame/lib/"

    # Templates
    cp "$PROJECT_DIR/src/whm/templates/"*.tmpl "$WHM_DOCROOT/cgi/frame/templates/"

    # Assets
    cp "$PROJECT_DIR/src/whm/assets/css/"*.css "$WHM_DOCROOT/cgi/frame/assets/css/"
    cp "$PROJECT_DIR/src/whm/assets/js/"*.js "$WHM_DOCROOT/cgi/frame/assets/js/"

    # WHM API
    mkdir -p "$CPANEL_BASE/Whostmgr/API/1"
    cp "$PROJECT_DIR/src/api/whm/Frame.pm" "$CPANEL_BASE/Whostmgr/API/1/"

    # Icon
    cp "$PROJECT_DIR/src/whm/plugin/icons/frame-icon.svg" "$WHM_DOCROOT/themes/x/icons/frame.svg"

    log_info "Installed WHM interface"
}

# Install cPanel interface
install_cpanel() {
    log_step "Installing cPanel interface..."

    # CGI scripts
    cp "$PROJECT_DIR/src/cpanel/index.live.cgi" "$CPANEL_FRONTEND/frame/"
    cp "$PROJECT_DIR/src/cpanel/api.live.cgi" "$CPANEL_FRONTEND/frame/"
    chmod 755 "$CPANEL_FRONTEND/frame/"*.cgi

    # Library
    cp "$PROJECT_DIR/src/cpanel/lib/FrameCpanel.pm" "$CPANEL_FRONTEND/frame/lib/"

    # Views
    cp "$PROJECT_DIR/src/cpanel/views/"*.tt "$CPANEL_FRONTEND/frame/views/"

    # Assets
    cp "$PROJECT_DIR/src/cpanel/assets/css/"*.css "$CPANEL_FRONTEND/frame/assets/css/"
    cp "$PROJECT_DIR/src/cpanel/assets/js/"*.js "$CPANEL_FRONTEND/frame/assets/js/"

    # cPanel UAPI
    mkdir -p "$CPANEL_BASE/Cpanel/API"
    cp "$PROJECT_DIR/src/api/cpanel/Frame.pm" "$CPANEL_BASE/Cpanel/API/"

    # Icon
    cp "$PROJECT_DIR/src/cpanel/plugin/icons/frame-icon.svg" "$CPANEL_FRONTEND/frame/"

    # Plugin registration
    mkdir -p "$CPANEL_BASE/base/frontend/jupiter/dynamicui"
    cp "$PROJECT_DIR/src/cpanel/plugin/dynamicui/frame.conf" "$CPANEL_BASE/base/frontend/jupiter/dynamicui/"

    # Feature registration - enables Frame for all accounts by default
    mkdir -p "/var/cpanel/features"
    echo "frame=1" >> "/var/cpanel/features/default" 2>/dev/null || true

    # Install cPanel AppConfig for the frame module
    cp "$PROJECT_DIR/src/cpanel/plugin/frame_cpanel.conf" /var/cpanel/apps/frame_cpanel.conf
    chmod 600 /var/cpanel/apps/frame_cpanel.conf
    chown root:root /var/cpanel/apps/frame_cpanel.conf

    log_info "Installed cPanel interface"
}

# Install Apache configuration
install_apache() {
    log_step "Installing Apache configuration..."

    # Main configuration
    cp "$PROJECT_DIR/src/apache/conf/frame.conf" "$APACHE_CONF/"

    # Templates
    cp "$PROJECT_DIR/src/apache/templates/"*.tmpl "$WHM_DOCROOT/cgi/frame/templates/apache/"

    # Error pages - install to both locations
    mkdir -p "/var/www/frame-error"
    mkdir -p "$WHM_DOCROOT/cgi/frame/error-pages"
    if ls "$PROJECT_DIR/src/apache/error-pages/"*.html &>/dev/null; then
        cp "$PROJECT_DIR/src/apache/error-pages/"*.html "/var/www/frame-error/"
        cp "$PROJECT_DIR/src/apache/error-pages/"*.html "$WHM_DOCROOT/cgi/frame/error-pages/"
    fi

    # Scripts
    cp "$PROJECT_DIR/src/apache/scripts/generate-vhost.pl" "$WHM_DOCROOT/cgi/frame/"
    cp "$PROJECT_DIR/src/apache/scripts/frame-apache-ctl.sh" /usr/local/bin/
    chmod 755 "$WHM_DOCROOT/cgi/frame/generate-vhost.pl"
    chmod 755 /usr/local/bin/frame-apache-ctl.sh

    # Initialize Apache configuration
    /usr/local/bin/frame-apache-ctl.sh init || true

    log_info "Installed Apache configuration"
}

# Register with cPanel
register_cpanel() {
    log_step "Registering with cPanel..."

    # Rebuild sprites
    if [ -x "$CPANEL_BASE/bin/rebuild_sprites" ]; then
        "$CPANEL_BASE/bin/rebuild_sprites" || true
    fi

    # Install WHM AppConfig
    log_info "Installing WHM AppConfig..."
    cp "$PROJECT_DIR/src/whm/plugin/frame_whm.conf" /var/cpanel/apps/frame_whm.conf
    chmod 600 /var/cpanel/apps/frame_whm.conf
    chown root:root /var/cpanel/apps/frame_whm.conf

    # Register with AppConfig (if available)
    if [ -x "$CPANEL_BASE/bin/register_appconfig" ]; then
        "$CPANEL_BASE/bin/register_appconfig" /var/cpanel/apps/frame_whm.conf 2>/dev/null || true
    fi

    # Enable unregistered apps as fallback (for older cPanel versions)
    if ! grep -q "permit_unregistered_apps_as_root=1" /var/cpanel/cpanel.config 2>/dev/null; then
        log_info "Enabling unregistered apps for root..."
        echo "permit_unregistered_apps_as_root=1" >> /var/cpanel/cpanel.config
    fi

    log_info "Registered with cPanel"
}

# Start services
start_services() {
    log_step "Starting services..."

    systemctl start frame-manager
    log_info "Frame manager started"

    # Reload Apache
    if command -v apachectl &>/dev/null; then
        apachectl graceful || true
        log_info "Apache reloaded"
    fi

    # Restart cPanel services to pick up plugin
    if [ -x "/scripts/restartsrv_cpsrvd" ]; then
        /scripts/restartsrv_cpsrvd || true
        log_info "cPanel services restarted"
    fi
}

# Development mode installation
install_dev() {
    log_info "Development mode: Creating symlinks instead of copying files"
    # In dev mode, we could create symlinks for easier development
    # For now, just run regular install
    install_full
}

# Full installation
install_full() {
    check_root
    check_cpanel
    check_dependencies

    echo ""
    echo "========================================"
    echo "  Frame cPanel Plugin Installer v$FRAME_VERSION"
    echo "========================================"
    echo ""

    create_directories
    install_config
    install_daemon
    install_systemd
    install_hooks
    install_whm
    install_cpanel
    install_apache
    register_cpanel
    start_services

    echo ""
    echo "========================================"
    log_info "Installation completed successfully!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. Access WHM > Plugins > Frame Manager"
    echo "  2. Configure global settings"
    echo "  3. Users can access Frame Applications in cPanel"
    echo ""
}

# Show usage
usage() {
    cat <<EOF
Frame cPanel Plugin Installer

Usage: $0 [options]

Options:
  --dev       Development mode (symlinks instead of copies)
  --help      Show this help message

Examples:
  $0          Full installation
  $0 --dev    Development installation

EOF
}

# Parse arguments
case "${1:-}" in
    --dev)
        install_dev
        ;;
    --help|-h)
        usage
        ;;
    *)
        install_full
        ;;
esac
