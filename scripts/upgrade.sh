#!/bin/bash
# Frame cPanel Plugin - Upgrade Script
# Upgrades the Frame cPanel plugin while preserving user data
#
# Usage: ./upgrade.sh

set -e

# Configuration
FRAME_VERSION="1.0.0"
CPANEL_BASE="/usr/local/cpanel"
WHM_DOCROOT="$CPANEL_BASE/whostmgr/docroot"
CPANEL_FRONTEND="$CPANEL_BASE/base/frontend/jupiter"
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

# Get current installed version
get_installed_version() {
    if [ -f "$FRAME_ETC/version" ]; then
        cat "$FRAME_ETC/version"
    else
        echo "0.0.0"
    fi
}

# Check if upgrade is needed
check_upgrade_needed() {
    local installed=$(get_installed_version)
    log_info "Installed version: $installed"
    log_info "New version: $FRAME_VERSION"

    if [ "$installed" = "$FRAME_VERSION" ]; then
        log_warn "Already at version $FRAME_VERSION"
        read -p "Reinstall anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            exit 0
        fi
    fi
}

# Backup configuration
backup_config() {
    log_step "Backing up configuration..."

    local backup_dir="/tmp/frame-backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"

    if [ -f "$FRAME_ETC/frame.conf" ]; then
        cp "$FRAME_ETC/frame.conf" "$backup_dir/"
    fi

    if [ -f "$FRAME_ETC/limits.conf" ]; then
        cp "$FRAME_ETC/limits.conf" "$backup_dir/"
    fi

    echo "$backup_dir"
}

# Stop services gracefully
stop_services() {
    log_step "Stopping services gracefully..."

    if systemctl is-active --quiet frame-manager 2>/dev/null; then
        systemctl stop frame-manager
        log_info "Stopped frame-manager service"
    fi
}

# Upgrade daemon
upgrade_daemon() {
    log_step "Upgrading Frame manager daemon..."

    local binary="$PROJECT_DIR/target/release/frame-manager"

    if [ ! -f "$binary" ]; then
        log_info "Building Frame manager..."
        cd "$PROJECT_DIR/src/manager"
        cargo build --release
        binary="$PROJECT_DIR/target/release/frame-manager"
    fi

    if [ -f "$binary" ]; then
        cp "$binary" /usr/local/bin/frame-manager
        chmod 755 /usr/local/bin/frame-manager
        log_info "Upgraded: /usr/local/bin/frame-manager"
    else
        log_error "Failed to build frame-manager"
        exit 1
    fi
}

# Upgrade systemd service
upgrade_systemd() {
    log_step "Upgrading systemd service..."

    cp "$PROJECT_DIR/packaging/systemd/frame-manager.service" /etc/systemd/system/
    systemctl daemon-reload
    log_info "Upgraded systemd service"
}

# Upgrade hooks
upgrade_hooks() {
    log_step "Upgrading cPanel hooks..."

    cp "$PROJECT_DIR/src/hooks/postwwwacct" "$CPANEL_BASE/scripts/postwwwacct/frame"
    cp "$PROJECT_DIR/src/hooks/prekillacct" "$CPANEL_BASE/scripts/prekillacct/frame"
    cp "$PROJECT_DIR/src/hooks/postacctremove" "$CPANEL_BASE/scripts/postacctremove/frame"

    chmod 755 "$CPANEL_BASE/scripts/postwwwacct/frame"
    chmod 755 "$CPANEL_BASE/scripts/prekillacct/frame"
    chmod 755 "$CPANEL_BASE/scripts/postacctremove/frame"

    log_info "Upgraded cPanel hooks"
}

# Upgrade WHM interface
upgrade_whm() {
    log_step "Upgrading WHM interface..."

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
    cp "$PROJECT_DIR/src/api/whm/Frame.pm" "$CPANEL_BASE/Whostmgr/API/1/"

    log_info "Upgraded WHM interface"
}

# Upgrade cPanel interface
upgrade_cpanel() {
    log_step "Upgrading cPanel interface..."

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
    cp "$PROJECT_DIR/src/api/cpanel/Frame.pm" "$CPANEL_BASE/Cpanel/API/"

    log_info "Upgraded cPanel interface"
}

# Upgrade Apache configuration
upgrade_apache() {
    log_step "Upgrading Apache configuration..."

    # Main configuration (but preserve user customizations if any)
    if [ -f "$APACHE_CONF/frame.conf" ]; then
        # Check if user modified it
        if ! diff -q "$PROJECT_DIR/src/apache/conf/frame.conf" "$APACHE_CONF/frame.conf" &>/dev/null; then
            cp "$APACHE_CONF/frame.conf" "$APACHE_CONF/frame.conf.bak"
            log_warn "Backed up modified frame.conf to frame.conf.bak"
        fi
    fi
    cp "$PROJECT_DIR/src/apache/conf/frame.conf" "$APACHE_CONF/"

    # Templates
    cp "$PROJECT_DIR/src/apache/templates/"*.tmpl "$WHM_DOCROOT/cgi/frame/templates/apache/"

    # Error pages
    cp "$PROJECT_DIR/src/apache/error-pages/"*.html "/var/www/frame-error/"

    # Scripts
    cp "$PROJECT_DIR/src/apache/scripts/generate-vhost.pl" "$WHM_DOCROOT/cgi/frame/"
    cp "$PROJECT_DIR/src/apache/scripts/frame-apache-ctl.sh" /usr/local/bin/
    chmod 755 "$WHM_DOCROOT/cgi/frame/generate-vhost.pl"
    chmod 755 /usr/local/bin/frame-apache-ctl.sh

    log_info "Upgraded Apache configuration"
}

# Update version file
update_version() {
    echo "$FRAME_VERSION" > "$FRAME_ETC/version"
    log_info "Updated version to $FRAME_VERSION"
}

# Start services
start_services() {
    log_step "Starting services..."

    systemctl start frame-manager
    log_info "Started frame-manager service"

    # Reload Apache
    if command -v apachectl &>/dev/null; then
        apachectl graceful || true
        log_info "Apache reloaded"
    fi
}

# Run migrations if needed
run_migrations() {
    log_step "Running migrations..."

    # Add version-specific migration logic here
    # Example:
    # local installed=$(get_installed_version)
    # if version_lt "$installed" "1.1.0"; then
    #     migrate_to_1_1_0
    # fi

    log_info "Migrations complete"
}

# Main
check_root

echo ""
echo "========================================"
echo "  Frame cPanel Plugin Upgrader"
echo "========================================"
echo ""

check_upgrade_needed

BACKUP_DIR=$(backup_config)
log_info "Configuration backed up to: $BACKUP_DIR"

stop_services
upgrade_daemon
upgrade_systemd
upgrade_hooks
upgrade_whm
upgrade_cpanel
upgrade_apache
run_migrations
update_version
start_services

echo ""
echo "========================================"
log_info "Upgrade completed successfully!"
echo "========================================"
echo ""
echo "Upgraded to version $FRAME_VERSION"
echo "Configuration backup: $BACKUP_DIR"
echo ""
