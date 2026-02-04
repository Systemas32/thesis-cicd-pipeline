#!/bin/bash
# Health Check Script for CI/CD Pipeline
# This script verifies the health of deployed services

set -e

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}
MAX_RETRIES=${3:-30}
RETRY_INTERVAL=${4:-10}

echo "Starting health checks for $RELEASE_NAME in namespace $NAMESPACE"

check_deployment_health() {
    local deployment=$1
    local retries=0
    
    echo "Checking deployment: $deployment"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        READY=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$READY" == "$DESIRED" ] && [ "$READY" != "0" ]; then
            echo "✓ Deployment $deployment is healthy ($READY/$DESIRED replicas ready)"
            return 0
        fi
        
        echo "  Waiting for $deployment... ($READY/$DESIRED ready, attempt $((retries+1))/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done
    
    echo "✗ Deployment $deployment failed health check"
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
exit 0
