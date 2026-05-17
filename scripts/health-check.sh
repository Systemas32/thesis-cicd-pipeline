#!/bin/bash
# Health Check Script for CI/CD Pipeline
# This script verifies the health of deployed services

set -e

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}
MAX_RETRIES=${3:-30}
RETRY_INTERVAL=${4:-10}

echo "Starting health checks for $RELEASE_NAME in namespace $NAMESPACE"
log_event health_check_started release="$RELEASE_NAME" namespace="$NAMESPACE" \
    max_retries="$MAX_RETRIES" retry_interval="$RETRY_INTERVAL"

check_deployment_health() {
    local deployment=$1
    local retries=0

    echo "Checking deployment: $deployment"

    local DESIRED READY UPDATED AVAILABLE TOTAL
    while [ $retries -lt $MAX_RETRIES ]; do
        DESIRED=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        READY=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        UPDATED=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
        AVAILABLE=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        TOTAL=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null)

        # Absent status fields are reported as empty by jsonpath; treat as 0.
        DESIRED=${DESIRED:-1}
        READY=${READY:-0}
        UPDATED=${UPDATED:-0}
        AVAILABLE=${AVAILABLE:-0}
        TOTAL=${TOTAL:-0}

        # A deployment is healthy only when the new revision has fully rolled
        # out: the desired number of replicas are updated, ready and available,
        # and no surplus pods from a previous revision remain (TOTAL == DESIRED).
        # Checking readyReplicas alone is not enough - during a stuck rolling
        # update the old healthy pod keeps readyReplicas at the desired count
        # while a broken new pod crash-loops alongside it.
        if [ "$READY" == "$DESIRED" ] && [ "$UPDATED" == "$DESIRED" ] \
            && [ "$AVAILABLE" == "$DESIRED" ] && [ "$TOTAL" == "$DESIRED" ] \
            && [ "$DESIRED" != "0" ]; then
            echo "✓ Deployment $deployment is healthy ($READY/$DESIRED ready, rollout complete)"
            log_event deployment_ready deployment="$deployment" \
                ready="$READY" desired="$DESIRED" updated="$UPDATED" \
                available="$AVAILABLE" total="$TOTAL"
            return 0
        fi

        echo "  Waiting for $deployment... (ready=$READY updated=$UPDATED available=$AVAILABLE total=$TOTAL desired=$DESIRED, attempt $((retries+1))/$MAX_RETRIES)"
        log_event health_check_attempt deployment="$deployment" \
            attempt="$((retries+1))" max_retries="$MAX_RETRIES" \
            ready="$READY" desired="$DESIRED" updated="$UPDATED" \
            available="$AVAILABLE" total="$TOTAL"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done

    echo "✗ Deployment $deployment failed health check"
    log_event health_check_failed deployment="$deployment" \
        reason="rollout_incomplete" ready="$READY" desired="$DESIRED" \
        updated="$UPDATED" available="$AVAILABLE" total="$TOTAL"
    return 1
}

check_endpoint_health() {
    local service=$1
    local port=$2
    local path=$3
    local retries=0
    
    echo "Checking endpoint: $service:$port$path"
    
    # Get service URL (for NodePort or port-forward)
    local url="http://localhost:$port$path"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" == "200" ]; then
            echo "✓ Endpoint $service$path is healthy (HTTP $HTTP_CODE)"
            return 0
        fi
        
        echo "  Waiting for $service$path... (HTTP $HTTP_CODE, attempt $((retries+1))/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done
    
    echo "✗ Endpoint $service$path failed health check"
    return 1
}

# Check deployments
check_deployment_health "${RELEASE_NAME}-api-gateway" || exit 1
check_deployment_health "${RELEASE_NAME}-user-service" || exit 1

echo ""
echo "All health checks passed!"
log_event health_check_passed release="$RELEASE_NAME"
exit 0
