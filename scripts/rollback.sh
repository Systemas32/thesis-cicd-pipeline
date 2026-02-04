#!/bin/bash
# Automated Rollback Script for CI/CD Pipeline
# Triggers rollback when health checks or tests fail

set -e

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}

echo "=========================================="
echo "INITIATING ROLLBACK for $RELEASE_NAME"
echo "=========================================="

# Get current revision
CURRENT_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')
echo "Current revision: $CURRENT_REVISION"

if [ "$CURRENT_REVISION" -le 1 ]; then
    echo "ERROR: Cannot rollback - already at first revision"
    exit 1
fi

# Get previous revision info
PREVIOUS_REVISION=$((CURRENT_REVISION - 1))
echo "Rolling back to revision: $PREVIOUS_REVISION"

# Perform rollback
echo "Executing: helm rollback $RELEASE_NAME $PREVIOUS_REVISION -n $NAMESPACE"
helm rollback "$RELEASE_NAME" "$PREVIOUS_REVISION" -n "$NAMESPACE" --wait --timeout 5m

# Verify rollback
echo ""
echo "Verifying rollback..."
NEW_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')

if [ "$NEW_REVISION" -gt "$CURRENT_REVISION" ]; then
    echo "✓ Rollback successful! New revision: $NEW_REVISION"
    
    # Run health checks after rollback
    echo ""
    echo "Running post-rollback health checks..."
    ./scripts/health-check.sh "$NAMESPACE" "$RELEASE_NAME" 20 5
    
    echo ""
    echo "=========================================="
    echo "ROLLBACK COMPLETED SUCCESSFULLY"
    echo "=========================================="
    exit 0
else
    echo "✗ Rollback may have failed. Please check manually."
    exit 1
fi
