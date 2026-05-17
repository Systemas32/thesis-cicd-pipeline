#!/bin/bash
# Scenario harness for the thesis CI/CD pipeline.
#
# Runs one experimental scenario end-to-end: deploys the relevant api-gateway
# image, monitors the health check, runs the smoke tests, triggers a rollback
# when something fails, and records every timestamp to a JSONL log file.
#
# Usage:
#   ./scripts/run-scenario.sh <scenario> <iteration>
#   e.g. ./scripts/run-scenario.sh broken-image 1
#
# Scenarios and expected outcomes:
#   successful   - deployment succeeds, smoke tests pass, no rollback
#   broken-image - health check fails, rollback triggered
#   broken-smoke - health check passes, smoke tests fail, rollback triggered
#   slow-start   - health check fails on timeout, rollback triggered

set -u

# --- Arguments -------------------------------------------------------------

SCENARIO=${1:-}
ITERATION=${2:-}

if [ -z "$SCENARIO" ] || [ -z "$ITERATION" ]; then
    echo "Usage: $0 <scenario> <iteration>"
    echo "  scenario: successful | broken-image | broken-smoke | slow-start"
    exit 2
fi

case "$SCENARIO" in
    successful)   IMAGE_TAG="latest" ;;
    broken-image) IMAGE_TAG="broken-image" ;;
    broken-smoke) IMAGE_TAG="broken-smoke" ;;
    slow-start)   IMAGE_TAG="slow-start" ;;
    *)
        echo "ERROR: unknown scenario '$SCENARIO'"
        echo "  expected: successful | broken-image | broken-smoke | slow-start"
        exit 2
        ;;
esac

# --- Configuration ---------------------------------------------------------

# Run everything from the repository root so the relative paths used by this
# script and by the child scripts (./scripts, ./helm) resolve correctly.
cd "$(dirname "$0")/.." || exit 1

NAMESPACE="default"
RELEASE_NAME="thesis-app"
CHART_PATH="./helm/thesis-app"
GATEWAY_SERVICE="${RELEASE_NAME}-api-gateway"
GATEWAY_LOCAL_PORT="30080"
GATEWAY_TARGET_PORT="5000"

# LOG_FILE is exported so the health-check and rollback child processes write
# their events into the same file as the harness.
export LOG_FILE="logs/run-${SCENARIO}-${ITERATION}-$(date +%s).jsonl"
mkdir -p logs

# shellcheck source=lib/log.sh
source "./scripts/lib/log.sh"

# --- Port-forward management ----------------------------------------------

PORT_FORWARD_PID=""

stop_port_forward() {
    if [ -n "$PORT_FORWARD_PID" ] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        kill "$PORT_FORWARD_PID" 2>/dev/null
        wait "$PORT_FORWARD_PID" 2>/dev/null
    fi
    PORT_FORWARD_PID=""
}

# Always tear the port-forward down, even if the script exits early.
trap stop_port_forward EXIT

start_port_forward() {
    echo "Starting port-forward ${GATEWAY_LOCAL_PORT} -> ${GATEWAY_SERVICE}:${GATEWAY_TARGET_PORT}"
    kubectl port-forward "svc/${GATEWAY_SERVICE}" \
        "${GATEWAY_LOCAL_PORT}:${GATEWAY_TARGET_PORT}" -n "$NAMESPACE" \
        >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!

    # Wait for the tunnel to accept connections before running the tests.
    local attempt=0
    while [ $attempt -lt 15 ]; do
        if curl -s -o /dev/null "http://localhost:${GATEWAY_LOCAL_PORT}/health"; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    echo "WARNING: port-forward did not become reachable within 15s"
    return 1
}

# --- Pre-conditions --------------------------------------------------------

echo "=========================================="
echo "SCENARIO: $SCENARIO (iteration $ITERATION)"
echo "Image tag: $IMAGE_TAG"
echo "Log file:  $LOG_FILE"
echo "=========================================="

# Minikube must be running.
if ! minikube status >/dev/null 2>&1; then
    echo "ERROR: Minikube is not running. Start it with 'minikube start'."
    exit 1
fi

# Clear any pods left in the Failed phase by prior runs.
kubectl delete pod --field-selector=status.phase=Failed \
    -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true

# Ensure a healthy prior revision exists so rollback has somewhere to go.
# If the release does not exist yet, install it on the 'latest' image and
# wait until it is ready.
if ! helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Release '$RELEASE_NAME' not found - installing baseline on 'latest'."
    if ! helm install "$RELEASE_NAME" "$CHART_PATH" -n "$NAMESPACE" \
        --set apiGateway.image.tag=latest --wait --timeout 5m; then
        echo "ERROR: baseline install failed."
        exit 1
    fi
fi

# --- Deployment ------------------------------------------------------------

log_event deployment_start release="$RELEASE_NAME" scenario="$SCENARIO" \
    iteration="$ITERATION" image_tag="$IMAGE_TAG"

echo ""
echo "Deploying $RELEASE_NAME with api-gateway tag '$IMAGE_TAG'..."
if ! helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" -n "$NAMESPACE" \
    --set apiGateway.image.tag="$IMAGE_TAG"; then
    echo "ERROR: helm upgrade failed."
    log_event scenario_completed scenario="$SCENARIO" iteration="$ITERATION" \
        outcome="deploy_failed"
    exit 1
fi

# --- Health check ----------------------------------------------------------

OUTCOME=""
NEEDS_ROLLBACK=0

echo ""
echo "Running health check..."
if ./scripts/health-check.sh "$NAMESPACE" "$RELEASE_NAME" 30 5; then
    HEALTH_OK=1
else
    HEALTH_OK=0
fi

# --- Smoke tests (only when the deployment is healthy) --------------------

if [ "$HEALTH_OK" -eq 1 ]; then
    echo ""
    echo "Health check passed - running smoke tests..."
    log_event smoke_tests_started release="$RELEASE_NAME"

    SMOKE_OK=0
    if start_port_forward; then
        # Invoke Robot via "python -m robot" so it works whether or not the
        # robot console script is on PATH.
        if python -m robot --outputdir "logs/robot-${SCENARIO}-${ITERATION}" \
            tests/smoke/smoke_tests.robot; then
            SMOKE_OK=1
        fi
    fi
    stop_port_forward

    if [ "$SMOKE_OK" -eq 1 ]; then
        echo "Smoke tests passed."
        log_event smoke_tests_passed release="$RELEASE_NAME"
    else
        echo "Smoke tests failed."
        log_event smoke_test_failed release="$RELEASE_NAME"
        NEEDS_ROLLBACK=1
    fi
else
    echo ""
    echo "Health check failed."
    NEEDS_ROLLBACK=1
fi

# --- Rollback --------------------------------------------------------------

if [ "$NEEDS_ROLLBACK" -eq 1 ]; then
    echo ""
    echo "Triggering rollback..."
    if ./scripts/rollback.sh "$NAMESPACE" "$RELEASE_NAME"; then
        OUTCOME="rolled_back"
    else
        OUTCOME="rollback_failed"
    fi
else
    OUTCOME="success"
fi

# --- Result ----------------------------------------------------------------

log_event scenario_completed scenario="$SCENARIO" iteration="$ITERATION" \
    outcome="$OUTCOME"

echo ""
echo "=========================================="
echo "SCENARIO COMPLETED: $SCENARIO (iteration $ITERATION)"
echo "Outcome:  $OUTCOME"
echo "Log file: $LOG_FILE"
echo "=========================================="

if [ "$OUTCOME" = "rollback_failed" ]; then
    exit 1
fi
exit 0
