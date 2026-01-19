#!/bin/bash
# Frame cPanel Plugin - Integration Test Script
# Tests the complete plugin installation and functionality

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_USER="${TEST_USER:-frametest}"
VERBOSE=false
CLEANUP=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        --user)
            TEST_USER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[TEST]${NC} $1"; }

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗${NC} $1"
    if [ "$VERBOSE" = true ] && [ -n "$2" ]; then
        echo "    $2"
    fi
}

skip() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "  ${YELLOW}○${NC} $1 (skipped)"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Integration tests must be run as root"
        exit 1
    fi
}

# Check if cPanel is installed
check_cpanel() {
    if [ ! -d "/usr/local/cpanel" ]; then
        log_error "cPanel not found - integration tests require cPanel"
        exit 1
    fi
}

# Test: Installation files exist
test_installation_files() {
    log_step "Testing installation files..."

    # Daemon
    if [ -f "/usr/local/bin/frame-manager" ]; then
        pass "Frame manager daemon exists"
    else
        fail "Frame manager daemon missing"
    fi

    # Systemd service
    if [ -f "/etc/systemd/system/frame-manager.service" ]; then
        pass "Systemd service file exists"
    else
        fail "Systemd service file missing"
    fi

    # Configuration
    if [ -f "/etc/frame/frame.conf" ]; then
        pass "Configuration file exists"
    else
        fail "Configuration file missing"
    fi

    # WHM interface
    if [ -d "/usr/local/cpanel/whostmgr/docroot/cgi/frame" ]; then
        pass "WHM interface directory exists"
    else
        fail "WHM interface directory missing"
    fi

    # cPanel interface
    if [ -d "/usr/local/cpanel/base/frontend/jupiter/frame" ]; then
        pass "cPanel interface directory exists"
    else
        fail "cPanel interface directory missing"
    fi

    # Apache configuration
    if [ -f "/etc/apache2/conf.d/frame.conf" ]; then
        pass "Apache configuration exists"
    else
        fail "Apache configuration missing"
    fi

    # Hooks
    if [ -f "/usr/local/cpanel/scripts/postwwwacct/frame" ]; then
        pass "Account creation hook exists"
    else
        fail "Account creation hook missing"
    fi
}

# Test: Service status
test_service_status() {
    log_step "Testing Frame manager service..."

    if systemctl is-enabled --quiet frame-manager 2>/dev/null; then
        pass "Service is enabled"
    else
        fail "Service is not enabled"
    fi

    if systemctl is-active --quiet frame-manager 2>/dev/null; then
        pass "Service is running"
    else
        fail "Service is not running"
    fi

    # Test API connectivity
    if curl -s http://127.0.0.1:9500/api/health > /dev/null 2>&1; then
        pass "API is responding"
    else
        fail "API is not responding"
    fi
}

# Test: WHM API
test_whm_api() {
    log_step "Testing WHM API..."

    # This requires WHM to be accessible
    if [ -f "/usr/local/cpanel/Whostmgr/API/1/Frame.pm" ]; then
        pass "WHM API module installed"
    else
        fail "WHM API module missing"
    fi

    # Check if module loads
    if perl -e 'use lib "/usr/local/cpanel"; eval { require Whostmgr::API::1::Frame; }; exit($@ ? 1 : 0)' 2>/dev/null; then
        pass "WHM API module loads successfully"
    else
        fail "WHM API module fails to load"
    fi
}

# Test: cPanel API
test_cpanel_api() {
    log_step "Testing cPanel API..."

    if [ -f "/usr/local/cpanel/Cpanel/API/Frame.pm" ]; then
        pass "cPanel API module installed"
    else
        fail "cPanel API module missing"
    fi

    # Check if module loads
    if perl -e 'use lib "/usr/local/cpanel"; eval { require Cpanel::API::Frame; }; exit($@ ? 1 : 0)' 2>/dev/null; then
        pass "cPanel API module loads successfully"
    else
        fail "cPanel API module fails to load"
    fi
}

# Test: Apache configuration
test_apache_config() {
    log_step "Testing Apache configuration..."

    # Test configuration syntax
    if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
        pass "Apache configuration syntax is valid"
    else
        fail "Apache configuration has errors"
    fi

    # Check if mod_proxy is loaded
    if apachectl -M 2>/dev/null | grep -q "proxy_module"; then
        pass "mod_proxy is loaded"
    else
        fail "mod_proxy is not loaded"
    fi

    # Check Frame configuration is included
    if [ -f "/etc/apache2/conf.d/frame.conf" ]; then
        pass "Frame Apache config exists"
    else
        fail "Frame Apache config missing"
    fi
}

# Test: Port allocation
test_port_allocation() {
    log_step "Testing port allocation..."

    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"user\":\"$TEST_USER\"}" \
        http://127.0.0.1:9500/api/ports/allocate)

    if echo "$response" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
        local port=$(echo "$response" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        pass "Port allocated: $port"

        # Release port
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"user\":\"$TEST_USER\"}" \
            http://127.0.0.1:9500/api/ports/release > /dev/null

        pass "Port released"
    elif echo "$response" | grep -q "already"; then
        skip "Port already allocated for test user"
    else
        fail "Port allocation failed" "$response"
    fi
}

# Test: Directory structure
test_directory_structure() {
    log_step "Testing directory structure..."

    local dirs=(
        "/var/frame"
        "/var/frame/instances"
        "/var/log/frame"
        "/etc/frame"
    )

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            pass "Directory exists: $dir"
        else
            fail "Directory missing: $dir"
        fi
    done
}

# Test: Permissions
test_permissions() {
    log_step "Testing file permissions..."

    # Daemon should be executable
    if [ -x "/usr/local/bin/frame-manager" ]; then
        pass "Daemon is executable"
    else
        fail "Daemon is not executable"
    fi

    # Config should be readable
    if [ -r "/etc/frame/frame.conf" ]; then
        pass "Config is readable"
    else
        fail "Config is not readable"
    fi

    # CGI scripts should be executable
    if [ -x "/usr/local/cpanel/whostmgr/docroot/cgi/frame/index.cgi" ]; then
        pass "WHM CGI is executable"
    else
        fail "WHM CGI is not executable"
    fi

    if [ -x "/usr/local/cpanel/base/frontend/jupiter/frame/index.live.cgi" ]; then
        pass "cPanel CGI is executable"
    else
        fail "cPanel CGI is not executable"
    fi
}

# Test: Hooks
test_hooks() {
    log_step "Testing cPanel hooks..."

    local hooks=(
        "/usr/local/cpanel/scripts/postwwwacct/frame"
        "/usr/local/cpanel/scripts/prekillacct/frame"
        "/usr/local/cpanel/scripts/postacctremove/frame"
    )

    for hook in "${hooks[@]}"; do
        if [ -x "$hook" ]; then
            pass "Hook is executable: $(basename $hook)"
        else
            fail "Hook missing or not executable: $hook"
        fi
    done
}

# Test: Metrics endpoint
test_metrics() {
    log_step "Testing metrics endpoint..."

    local response=$(curl -s http://127.0.0.1:9500/metrics)

    if echo "$response" | grep -q "frame_instances"; then
        pass "Metrics endpoint returns data"
    else
        fail "Metrics endpoint not working"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Integration Test Summary"
    echo "========================================"
    echo "Tests run:     $TESTS_RUN"
    echo -e "Tests passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo ""

    local exit_code=0
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit_code=1
    fi

    return $exit_code
}

# Cleanup
cleanup() {
    if [ "$CLEANUP" = true ]; then
        log_info "Cleaning up test artifacts..."
        # Release any allocated ports for test user
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"user\":\"$TEST_USER\"}" \
            http://127.0.0.1:9500/api/ports/release > /dev/null 2>&1 || true
    fi
}

# Main
main() {
    echo "========================================"
    echo "Frame cPanel Plugin Integration Tests"
    echo "========================================"
    echo "Test User: $TEST_USER"
    echo ""

    check_root
    check_cpanel

    # Run tests
    test_installation_files
    test_directory_structure
    test_permissions
    test_service_status
    test_apache_config
    test_whm_api
    test_cpanel_api
    test_port_allocation
    test_hooks
    test_metrics

    # Cleanup
    cleanup

    # Summary
    print_summary
}

trap cleanup EXIT
main "$@"
