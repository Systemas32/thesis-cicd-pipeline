#!/bin/bash
# Manual baseline harness for the thesis CI/CD pipeline.
#
# Records human-paced timestamps for an equivalent *manual* deploy and
# rollback cycle, so Chapter 4 can compare the automated system against a
# manual baseline. This script automates nothing: it prompts the operator,
# waits for ENTER at each stage, and timestamps the events to a JSONL log in
# the same format as the automated runs.
#
# Usage:
#   ./scripts/run-manual-baseline.sh <scenario> <iteration>
#   e.g. ./scripts/run-manual-baseline.sh broken-image 1

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

# Run from the repository root so the log.sh path and the suggested commands
# resolve correctly.
cd "$(dirname "$0")/.." || exit 1

NAMESPACE="default"
RELEASE_NAME="thesis-app"
CHART_PATH="./helm/thesis-app"

export LOG_FILE="logs/manual-${SCENARIO}-${ITERATION}-$(date +%s).jsonl"
mkdir -p logs

# shellcheck source=lib/log.sh
source "./scripts/lib/log.sh"

# Image-build commands for the chosen scenario.
if [ "$SCENARIO" = "successful" ]; then
    BUILD_CMD="docker build -t systemas32/api-gateway:latest ./microservices/api-gateway"
    PUSH_CMD="docker push systemas32/api-gateway:latest"
else
    BUILD_CMD="docker build -f microservices/api-gateway/scenarios/Dockerfile.${SCENARIO} -t systemas32/api-gateway:${IMAGE_TAG} ./microservices/api-gateway"
    PUSH_CMD="docker push systemas32/api-gateway:${IMAGE_TAG}"
fi

HELM_CMD="helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} -n ${NAMESPACE} --set apiGateway.image.tag=${IMAGE_TAG}"

# --- Prompt helper ---------------------------------------------------------

# prompt_enter <message>
# Prints the message and blocks until the operator presses ENTER.
prompt_enter() {
    echo ""
    read -r -p ">>> $1 [press ENTER] " _
}

# --- Run -------------------------------------------------------------------

echo "=========================================="
echo "MANUAL BASELINE: $SCENARIO (iteration $ITERATION)"
echo "Image tag: $IMAGE_TAG"
echo "Log file:  $LOG_FILE"
echo "=========================================="
echo ""
echo "This run is operated by hand. Perform each step yourself in another"
echo "terminal, then press ENTER here so the timestamp is recorded."

prompt_enter "Ready to start the manual deployment cycle?"
log_event manual_start scenario="$SCENARIO" iteration="$ITERATION" \
    image_tag="$IMAGE_TAG"

# Stage 1: build and push the image.
echo ""
echo "STEP 1 - Build and push the api-gateway image. Suggested commands:"
echo "  $BUILD_CMD"
echo "  $PUSH_CMD"
prompt_enter "Press ENTER once the image build and push are complete."
log_event manual_image_ready scenario="$SCENARIO" iteration="$ITERATION"

# Stage 2: deploy with Helm.
echo ""
echo "STEP 2 - Deploy with Helm. Suggested command:"
echo "  $HELM_CMD"
prompt_enter "Press ENTER once the helm upgrade has completed."
log_event manual_deployment_done scenario="$SCENARIO" iteration="$ITERATION"

# Stage 3: verify the deployment by hand.
echo ""
echo "STEP 3 - Verify the pods by hand, e.g.:"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo ""
echo "Press ENTER once all pods report Ready, or type F then ENTER if you"
echo "observe a failure (crash loop, pods not becoming Ready, errors)."
read -r -p ">>> ENTER = healthy, F = failure: " VERDICT

OUTCOME=""
if [ "$VERDICT" = "F" ] || [ "$VERDICT" = "f" ]; then
    log_event manual_failure_detected scenario="$SCENARIO" \
        iteration="$ITERATION"

    # Stage 4: manual rollback.
    echo ""
    echo "STEP 4 - Roll back by hand. Suggested command:"
    echo "  helm rollback ${RELEASE_NAME} -n ${NAMESPACE}"
    prompt_enter "Press ENTER at the moment you START the rollback."
    log_event manual_rollback_start scenario="$SCENARIO" \
        iteration="$ITERATION"

    prompt_enter "Press ENTER once the rollback is complete and pods are healthy."
    log_event manual_rollback_done scenario="$SCENARIO" \
        iteration="$ITERATION"

    OUTCOME="rolled_back"
else
    log_event manual_health_verified scenario="$SCENARIO" \
        iteration="$ITERATION"
    OUTCOME="success"
fi

log_event manual_completed scenario="$SCENARIO" iteration="$ITERATION" \
    outcome="$OUTCOME"

echo ""
echo "=========================================="
echo "MANUAL BASELINE COMPLETED: $SCENARIO (iteration $ITERATION)"
echo "Outcome:  $OUTCOME"
echo "Log file: $LOG_FILE"
echo "=========================================="
