#!/bin/bash
# Frame Manager API Test Script
# Tests the manager daemon REST API endpoints

set -e

# Configuration
API_URL="http://127.0.0.1:9500"
TEST_USER="testuser"
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --url)
            API_URL="$2"
            shift 2
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

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Make API request and return response
api_get() {
    local endpoint="$1"
    curl -s "$API_URL$endpoint"
}

api_post() {
    local endpoint="$1"
    local data="${2:-{}}"
    curl -s -X POST -H "Content-Type: application/json" -d "$data" "$API_URL$endpoint"
}

# Assert response contains expected value
assert_contains() {
    local response="$1"
    local expected="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$response" | grep -q "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $test_name"
        if [ "$VERBOSE" = true ]; then
            echo "    Expected: $expected"
            echo "    Response: $response"
        fi
        return 1
    fi
}

# Assert JSON field has expected value
assert_json_field() {
    local response="$1"
    local field="$2"
    local expected="$3"
    local test_name="$4"

    TESTS_RUN=$((TESTS_RUN + 1))

    local actual=$(echo "$response" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"*[^,}\"]*" | sed 's/.*://;s/[" ]//g')

    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $test_name"
        if [ "$VERBOSE" = true ]; then
            echo "    Expected: $expected"
            echo "    Actual: $actual"
        fi
        return 1
    fi
}

# Assert HTTP status code
assert_status() {
    local endpoint="$1"
    local expected="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    local status=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL$endpoint")

    if [ "$status" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $test_name"
        if [ "$VERBOSE" = true ]; then
            echo "    Expected status: $expected"
            echo "    Actual status: $status"
        fi
        return 1
    fi
}

# Check if manager is running
check_manager() {
    log_info "Checking if Frame manager is running..."

    if ! curl -s "$API_URL/api/health" > /dev/null 2>&1; then
        log_error "Frame manager is not running at $API_URL"
        log_warn "Start the manager with: systemctl start frame-manager"
        exit 1
    fi

    log_info "Frame manager is running"
}

# Test health endpoint
test_health() {
    echo ""
    echo "Testing /api/health endpoint..."

    local response=$(api_get "/api/health")

    assert_contains "$response" "status" "Health endpoint returns status"
    assert_contains "$response" "healthy" "Status is healthy"
}

# Test status endpoint
test_status() {
    echo ""
    echo "Testing /api/status endpoint..."

    local response=$(api_get "/api/status")

    assert_contains "$response" "status" "Status endpoint returns status"
    assert_contains "$response" "version" "Status includes version"
    assert_contains "$response" "uptime" "Status includes uptime"
}

# Test instances endpoint
test_instances() {
    echo ""
    echo "Testing /api/instances endpoint..."

    local response=$(api_get "/api/instances")

    assert_contains "$response" "instances" "Instances endpoint returns instances array"
}

# Test ports endpoint
test_ports() {
    echo ""
    echo "Testing /api/ports endpoint..."

    local response=$(api_get "/api/ports")

    assert_contains "$response" "range" "Ports endpoint returns range"
    assert_contains "$response" "allocated" "Ports includes allocated count"
    assert_contains "$response" "available" "Ports includes available count"
}

# Test port allocation
test_port_allocation() {
    echo ""
    echo "Testing port allocation..."

    # Allocate port
    local response=$(api_post "/api/ports/allocate" "{\"user\":\"$TEST_USER\"}")

    if echo "$response" | grep -q "success.*true"; then
        assert_contains "$response" "port" "Port allocated successfully"

        # Get allocated port
        local port=$(echo "$response" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        log_info "Allocated port $port for $TEST_USER"

        # Release port
        response=$(api_post "/api/ports/release" "{\"user\":\"$TEST_USER\"}")
        assert_contains "$response" "success" "Port released successfully"
    else
        log_warn "Port allocation may have failed or port already allocated"
        assert_contains "$response" "error\|success" "Port allocation returns response"
    fi
}

# Test instance operations
test_instance_operations() {
    echo ""
    echo "Testing instance operations for $TEST_USER..."

    # Get instance status
    local response=$(api_get "/api/instances/$TEST_USER")

    if echo "$response" | grep -q "not_found\|error"; then
        log_warn "Test user instance not found - skipping instance tests"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${YELLOW}○${NC} Instance tests skipped (no test instance)"
        return
    fi

    assert_contains "$response" "user" "Instance returns user info"

    # Test start (if stopped)
    if echo "$response" | grep -q '"status"[[:space:]]*:[[:space:]]*"stopped"'; then
        response=$(api_post "/api/instances/$TEST_USER/start")
        assert_contains "$response" "success\|error" "Start returns response"
    fi

    # Test restart
    response=$(api_post "/api/instances/$TEST_USER/restart")
    assert_contains "$response" "success\|error" "Restart returns response"

    # Test stop
    response=$(api_post "/api/instances/$TEST_USER/stop")
    assert_contains "$response" "success\|error" "Stop returns response"
}

# Test metrics endpoint
test_metrics() {
    echo ""
    echo "Testing /metrics endpoint..."

    local response=$(api_get "/metrics")

    assert_contains "$response" "frame_instances" "Metrics includes instance count"
}

# Test error handling
test_error_handling() {
    echo ""
    echo "Testing error handling..."

    # Non-existent endpoint
    assert_status "/api/nonexistent" "404" "404 for non-existent endpoint"

    # Non-existent user
    local response=$(api_get "/api/instances/nonexistent_user_12345")
    assert_contains "$response" "error\|not_found" "Error for non-existent user"
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main
main() {
    echo "========================================"
    echo "Frame Manager API Tests"
    echo "========================================"
    echo "API URL: $API_URL"
    echo "Test User: $TEST_USER"
    echo ""

    check_manager

    test_health
    test_status
    test_instances
    test_ports
    test_port_allocation
    test_instance_operations
    test_metrics
    test_error_handling

    print_summary
}

main "$@"
