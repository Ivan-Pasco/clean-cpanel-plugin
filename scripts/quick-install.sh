#!/bin/bash
# Frame cPanel Plugin - Quick Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/cleanlanguage/frame-cpanel/main/scripts/quick-install.sh | sudo bash
#
# Options (set as environment variables):
#   FRAME_VERSION - Specific version to install (default: latest)
#   FRAME_SKIP_DEPS - Skip dependency check (default: false)

set -e

# Configuration
GITHUB_REPO="cleanlanguage/frame-cpanel"
INSTALL_DIR="/tmp/frame-cpanel-install"
VERSION="${FRAME_VERSION:-latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Print banner
print_banner() {
    echo ""
    echo "========================================"
    echo "  Frame cPanel Plugin Quick Installer"
    echo "========================================"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This installer must be run as root"
        echo ""
        echo "Usage: curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/scripts/quick-install.sh | sudo bash"
        exit 1
    fi
}

# Check for cPanel
check_cpanel() {
    log_step "Checking for cPanel..."

    if [ ! -d "/usr/local/cpanel" ]; then
        log_error "cPanel not found!"
        echo ""
        echo "This plugin requires cPanel/WHM to be installed."
        echo "Visit https://cpanel.net for installation instructions."
        exit 1
    fi

    if [ -f "/usr/local/cpanel/version" ]; then
        local version=$(cat /usr/local/cpanel/version | cut -d. -f1,2)
        log_info "Found cPanel version: $version"

        # Check minimum version (102)
        local major=$(echo $version | cut -d. -f1)
        if [ "$major" -lt 102 ]; then
            log_warn "cPanel version $version may not be fully supported"
            log_warn "Recommended: cPanel 102 or later"
        fi
    fi
}

# Check dependencies
check_dependencies() {
    if [ "${FRAME_SKIP_DEPS:-false}" = "true" ]; then
        log_warn "Skipping dependency check"
        return
    fi

    log_step "Checking dependencies..."

    # Check for curl or wget
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi

    # Check for tar
    if ! command -v tar &>/dev/null; then
        log_error "tar not found. Please install tar."
        exit 1
    fi

    log_info "Dependencies OK"
}

# Get latest version from GitHub
get_latest_version() {
    log_step "Fetching latest version..."

    if command -v curl &>/dev/null; then
        VERSION=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    else
        VERSION=$(wget -qO- "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    fi

    if [ -z "$VERSION" ]; then
        log_error "Could not determine latest version"
        echo ""
        echo "You can specify a version manually:"
        echo "  FRAME_VERSION=1.0.0 curl -fsSL ... | sudo bash"
        exit 1
    fi

    log_info "Latest version: $VERSION"
}

# Download release
download_release() {
    log_step "Downloading Frame cPanel Plugin v$VERSION..."

    local url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/frame-cpanel-$VERSION.tar.gz"

    # Create install directory
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Download
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "frame-cpanel-$VERSION.tar.gz"
    else
        wget -q "$url" -O "frame-cpanel-$VERSION.tar.gz"
    fi

    if [ ! -f "frame-cpanel-$VERSION.tar.gz" ]; then
        log_error "Download failed"
        exit 1
    fi

    log_info "Download complete"
}

# Verify download (optional)
verify_download() {
    log_step "Verifying download..."

    local checksum_url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/frame-cpanel-$VERSION.tar.gz.sha256"

    if command -v curl &>/dev/null; then
        curl -fsSL "$checksum_url" -o "frame-cpanel-$VERSION.tar.gz.sha256" 2>/dev/null || true
    else
        wget -q "$checksum_url" -O "frame-cpanel-$VERSION.tar.gz.sha256" 2>/dev/null || true
    fi

    if [ -f "frame-cpanel-$VERSION.tar.gz.sha256" ]; then
        if sha256sum -c "frame-cpanel-$VERSION.tar.gz.sha256" 2>/dev/null; then
            log_info "Checksum verified"
        else
            log_warn "Checksum verification failed - continuing anyway"
        fi
    else
        log_warn "No checksum file available - skipping verification"
    fi
}

# Extract and install
install_package() {
    log_step "Extracting package..."

    tar -xzf "frame-cpanel-$VERSION.tar.gz"
    cd "frame-cpanel-$VERSION"

    log_step "Running installer..."

    if [ -f "scripts/install.sh" ]; then
        chmod +x scripts/install.sh
        ./scripts/install.sh
    else
        log_error "Install script not found in package"
        exit 1
    fi
}

# Cleanup
cleanup() {
    log_step "Cleaning up..."
    rm -rf "$INSTALL_DIR"
    log_info "Cleanup complete"
}

# Print success message
print_success() {
    echo ""
    echo "========================================"
    echo -e "  ${GREEN}Installation Complete!${NC}"
    echo "========================================"
    echo ""
    echo "Frame cPanel Plugin v$VERSION has been installed."
    echo ""
    echo "Next steps:"
    echo "  1. Access WHM > Plugins > Frame Manager"
    echo "  2. Configure global settings"
    echo "  3. Users can access Frame Applications in cPanel"
    echo ""
    echo "Documentation: https://github.com/$GITHUB_REPO"
    echo ""
}

# Main
main() {
    print_banner
    check_root
    check_cpanel
    check_dependencies

    if [ "$VERSION" = "latest" ]; then
        get_latest_version
    else
        log_info "Installing version: $VERSION"
    fi

    download_release
    verify_download
    install_package
    cleanup
    print_success
}

# Handle errors
trap 'log_error "Installation failed at line $LINENO"; cleanup; exit 1' ERR

main "$@"
