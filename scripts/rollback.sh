#!/bin/bash
# Automated Rollback Script for CI/CD Pipeline
# Triggers rollback when health checks or tests fail

set -e

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}

echo "=========================================="
echo "INITIATING ROLLBACK for $RELEASE_NAME"
echo "=========================================="
log_event rollback_triggered release="$RELEASE_NAME" namespace="$NAMESPACE"

# Get current revision
CURRENT_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')
echo "Current revision: $CURRENT_REVISION"

if [ "$CURRENT_REVISION" -le 1 ]; then
    echo "ERROR: Cannot rollback - already at first revision"
    log_event rollback_failed reason="no_previous_revision" \
        current_revision="$CURRENT_REVISION"
    exit 1
fi

# Get previous revision info
PREVIOUS_REVISION=$((CURRENT_REVISION - 1))
echo "Rolling back to revision: $PREVIOUS_REVISION"

# Perform rollback
echo "Executing: helm rollback $RELEASE_NAME $PREVIOUS_REVISION -n $NAMESPACE"
log_event rollback_executing release="$RELEASE_NAME" \
    from_revision="$CURRENT_REVISION" to_revision="$PREVIOUS_REVISION"
helm rollback "$RELEASE_NAME" "$PREVIOUS_REVISION" -n "$NAMESPACE" --wait --timeout 5m

# Verify rollback
echo ""
echo "Verifying rollback..."
NEW_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')

if [ "$NEW_REVISION" -gt "$CURRENT_REVISION" ]; then
    echo "✓ Rollback successful! New revision: $NEW_REVISION"
    log_event rollback_completed release="$RELEASE_NAME" \
        from_revision="$CURRENT_REVISION" to_revision="$NEW_REVISION"

    # Run health checks after rollback
    echo ""
    echo "Running post-rollback health checks..."
    ./scripts/health-check.sh "$NAMESPACE" "$RELEASE_NAME" 20 5

    log_event post_rollback_health_check_passed release="$RELEASE_NAME" \
        revision="$NEW_REVISION"

    echo ""
    echo "=========================================="
    echo "ROLLBACK COMPLETED SUCCESSFULLY"
    echo "=========================================="
    exit 0
else
    echo "✗ Rollback may have failed. Please check manually."
    log_event rollback_failed reason="revision_not_advanced" \
        from_revision="$CURRENT_REVISION" new_revision="$NEW_REVISION"
    exit 1
fi
