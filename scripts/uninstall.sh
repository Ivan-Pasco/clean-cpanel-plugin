#!/bin/bash
# Frame cPanel Plugin - Uninstallation Script
# Removes all components of the Frame cPanel plugin
#
# Usage: ./uninstall.sh [--keep-data]

set -e

# Configuration
CPANEL_BASE="/usr/local/cpanel"
WHM_DOCROOT="$CPANEL_BASE/whostmgr/docroot"
CPANEL_FRONTEND="$CPANEL_BASE/base/frontend/jupiter"
FRAME_VAR="/var/frame"
FRAME_LOG="/var/log/frame"
FRAME_ETC="/etc/frame"
APACHE_CONF="/etc/apache2/conf.d"

# Options
KEEP_DATA=false

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

# Confirm uninstallation
confirm_uninstall() {
    echo ""
    echo "========================================"
    echo "  Frame cPanel Plugin Uninstaller"
    echo "========================================"
    echo ""

    if [ "$KEEP_DATA" = true ]; then
        log_warn "User data will be preserved"
    else
        log_warn "This will remove ALL Frame data including user applications!"
    fi

    echo ""
    read -p "Are you sure you want to uninstall? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
}

# Stop services
stop_services() {
    log_step "Stopping services..."

    # Stop all user instances first
    if [ -x /usr/local/bin/frame-manager ]; then
        /usr/local/bin/frame-manager stop-all 2>/dev/null || true
    fi

    # Stop Frame manager
    if systemctl is-active --quiet frame-manager 2>/dev/null; then
        systemctl stop frame-manager
        log_info "Stopped frame-manager service"
    fi

    # Disable service
    if systemctl is-enabled --quiet frame-manager 2>/dev/null; then
        systemctl disable frame-manager
        log_info "Disabled frame-manager service"
    fi
}

# Remove systemd service
remove_systemd() {
    log_step "Removing systemd service..."

    if [ -f /etc/systemd/system/frame-manager.service ]; then
        rm -f /etc/systemd/system/frame-manager.service
        systemctl daemon-reload
        log_info "Removed systemd service"
    fi
}

# Remove daemon
remove_daemon() {
    log_step "Removing Frame manager daemon..."

    if [ -f /usr/local/bin/frame-manager ]; then
        rm -f /usr/local/bin/frame-manager
        log_info "Removed: /usr/local/bin/frame-manager"
    fi

    if [ -f /usr/local/bin/frame-apache-ctl.sh ]; then
        rm -f /usr/local/bin/frame-apache-ctl.sh
        log_info "Removed: /usr/local/bin/frame-apache-ctl.sh"
    fi
}

# Remove cPanel hooks
remove_hooks() {
    log_step "Removing cPanel hooks..."

    local hooks=(
        "$CPANEL_BASE/scripts/postwwwacct/frame"
        "$CPANEL_BASE/scripts/prekillacct/frame"
        "$CPANEL_BASE/scripts/postacctremove/frame"
    )

    for hook in "${hooks[@]}"; do
        if [ -f "$hook" ]; then
            rm -f "$hook"
            log_info "Removed: $hook"
        fi
    done
}

# Remove WHM interface
remove_whm() {
    log_step "Removing WHM interface..."

    # Remove CGI directory
    if [ -d "$WHM_DOCROOT/cgi/frame" ]; then
        rm -rf "$WHM_DOCROOT/cgi/frame"
        log_info "Removed: $WHM_DOCROOT/cgi/frame"
    fi

    # Remove WHM API
    if [ -f "$CPANEL_BASE/Whostmgr/API/1/Frame.pm" ]; then
        rm -f "$CPANEL_BASE/Whostmgr/API/1/Frame.pm"
        log_info "Removed: $CPANEL_BASE/Whostmgr/API/1/Frame.pm"
    fi

    # Remove icon
    if [ -f "$WHM_DOCROOT/themes/x/icons/frame.svg" ]; then
        rm -f "$WHM_DOCROOT/themes/x/icons/frame.svg"
        log_info "Removed WHM icon"
    fi
}

# Remove cPanel interface
remove_cpanel() {
    log_step "Removing cPanel interface..."

    # Remove frontend directory
    if [ -d "$CPANEL_FRONTEND/frame" ]; then
        rm -rf "$CPANEL_FRONTEND/frame"
        log_info "Removed: $CPANEL_FRONTEND/frame"
    fi

    # Remove cPanel UAPI
    if [ -f "$CPANEL_BASE/Cpanel/API/Frame.pm" ]; then
        rm -f "$CPANEL_BASE/Cpanel/API/Frame.pm"
        log_info "Removed: $CPANEL_BASE/Cpanel/API/Frame.pm"
    fi

    # Remove dynamicui config
    if [ -f "$CPANEL_FRONTEND/dynamicui/frame.conf" ]; then
        rm -f "$CPANEL_FRONTEND/dynamicui/frame.conf"
        log_info "Removed dynamicui configuration"
    fi
}

# Remove Apache configuration
remove_apache() {
    log_step "Removing Apache configuration..."

    # Remove Frame configuration directory
    if [ -d "$APACHE_CONF/frame" ]; then
        rm -rf "$APACHE_CONF/frame"
        log_info "Removed: $APACHE_CONF/frame"
    fi

    # Remove main configuration
    if [ -f "$APACHE_CONF/frame.conf" ]; then
        rm -f "$APACHE_CONF/frame.conf"
        log_info "Removed: $APACHE_CONF/frame.conf"
    fi

    # Remove error pages
    if [ -d "/var/www/frame-error" ]; then
        rm -rf "/var/www/frame-error"
        log_info "Removed: /var/www/frame-error"
    fi

    # Remove include from pre_virtualhost
    local include_conf="$APACHE_CONF/includes/pre_virtualhost_global.conf"
    if [ -f "$include_conf" ]; then
        sed -i '/frame\.conf/d' "$include_conf" 2>/dev/null || true
    fi

    # Reload Apache
    if command -v apachectl &>/dev/null; then
        apachectl graceful 2>/dev/null || true
        log_info "Apache reloaded"
    fi
}

# Remove configuration files
remove_config() {
    log_step "Removing configuration files..."

    if [ -d "$FRAME_ETC" ]; then
        rm -rf "$FRAME_ETC"
        log_info "Removed: $FRAME_ETC"
    fi
}

# Remove data (if not keeping)
remove_data() {
    if [ "$KEEP_DATA" = true ]; then
        log_warn "Keeping user data in $FRAME_VAR"
        return
    fi

    log_step "Removing user data..."

    if [ -d "$FRAME_VAR" ]; then
        rm -rf "$FRAME_VAR"
        log_info "Removed: $FRAME_VAR"
    fi

    if [ -d "$FRAME_LOG" ]; then
        rm -rf "$FRAME_LOG"
        log_info "Removed: $FRAME_LOG"
    fi
}

# Unregister from cPanel
unregister_cpanel() {
    log_step "Unregistering from cPanel..."

    # Rebuild sprites
    if [ -x "$CPANEL_BASE/bin/rebuild_sprites" ]; then
        "$CPANEL_BASE/bin/rebuild_sprites" 2>/dev/null || true
    fi

    log_info "Unregistered from cPanel"
}

# Show usage
usage() {
    cat <<EOF
Frame cPanel Plugin Uninstaller

Usage: $0 [options]

Options:
  --keep-data   Keep user data (applications, logs)
  --help        Show this help message

Examples:
  $0              Complete uninstallation
  $0 --keep-data  Uninstall but keep user data

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main
check_root
confirm_uninstall

stop_services
remove_systemd
remove_daemon
remove_hooks
remove_whm
remove_cpanel
remove_apache
remove_config
remove_data
unregister_cpanel

echo ""
echo "========================================"
log_info "Uninstallation completed!"
echo "========================================"
echo ""

if [ "$KEEP_DATA" = true ]; then
    echo "User data has been preserved in $FRAME_VAR"
    echo "To remove it manually: rm -rf $FRAME_VAR"
fi
