#!/bin/bash
# Structured event logging for the thesis CI/CD pipeline.
#
# Source this file from a pipeline script, then call log_event to append a
# single JSON line to $LOG_FILE for each significant event. The resulting
# JSONL file is consumed by scripts/aggregate-results.py to compute the
# Chapter 4 metrics (time-to-detect, MTTR).
#
# Usage:
#   source "$(dirname "$0")/lib/log.sh"
#   log_event deployment_start release=thesis-app scenario=broken-image
#
# The scenario harness (run-scenario.sh) sets LOG_FILE before invoking the
# pipeline scripts. When a script is run standalone, LOG_FILE falls back to a
# timestamped file under logs/ so logging never fails.

if [ -z "${LOG_FILE:-}" ]; then
    LOG_FILE="logs/run-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
fi
mkdir -p "$(dirname "$LOG_FILE")"

# log_event <event-name> [key=value ...]
# Appends one JSON object to $LOG_FILE with an ISO 8601 UTC millisecond
# timestamp, the event name, and any extra key=value context fields. All
# context values are written as JSON strings.
log_event() {
    local event=$1
    shift

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

    local jq_args=(--arg timestamp "$timestamp" --arg event "$event")
    local filter='{timestamp: $timestamp, event: $event'

    local pair key value
    for pair in "$@"; do
        key=${pair%%=*}
        value=${pair#*=}
        jq_args+=(--arg "$key" "$value")
        filter+=", $key: \$$key"
    done
    filter+='}'

    jq -c -n "${jq_args[@]}" "$filter" >> "$LOG_FILE"
}
