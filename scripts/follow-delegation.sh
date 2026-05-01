#!/usr/bin/env bash
# Expected host/container tools: bash, jq, tail.
# Default path resolution assumes WORKSPACE=/workspace and
# DELEGATIONS_ROOT=$WORKSPACE/delegations unless overridden.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: follow-delegation <run-id|run-dir>

Continuously follow delegation log files. If the run directory or log files do not
exist yet, wait for them instead of failing.
EOF
}

[[ $# -eq 1 ]] || { usage; exit 64; }

WORKSPACE=${WORKSPACE:-/workspace}
DELEGATIONS_ROOT=${DELEGATIONS_ROOT:-$WORKSPACE/delegations}
INPUT=$1

if [[ "$INPUT" = /* ]]; then
  RUN_DIR=$INPUT
else
  RUN_DIR="$DELEGATIONS_ROOT/$INPUT"
fi

RUN_ID=$(basename "$RUN_DIR")
LOG_FILE="$RUN_DIR/10-worker-log.md"
SUMMARY_FILE="$RUN_DIR/12-output-summary.md"
STATUS_FILE="$RUN_DIR/status.json"

note() {
  printf '[follow-delegation] %s\n' "$*" >&2
}

wait_for_path() {
  local path=$1
  local label=$2
  until [[ -e "$path" ]]; do
    note "waiting for $label: $path"
    sleep 2
  done
}

wait_for_path "$RUN_DIR" "run directory"
wait_for_path "$STATUS_FILE" "status file"
wait_for_path "$LOG_FILE" "worker log"
wait_for_path "$SUMMARY_FILE" "summary file"

note "following run: $RUN_ID"
note "status: $STATUS_FILE"
note "log: $LOG_FILE"
note "summary: $SUMMARY_FILE"

(
  last_state=''
  while true; do
    if [[ -r "$STATUS_FILE" ]]; then
      state=$(jq -r '.state // "unknown"' "$STATUS_FILE" 2>/dev/null || echo unknown)
      if [[ "$state" != "$last_state" ]]; then
        note "state -> $state"
        last_state=$state
      fi
      if [[ "$state" = done || "$state" = failed ]]; then
        note "terminal state reached: $state"
        exit 0
      fi
    fi
    sleep 2
  done
) &
status_watcher=$!

cleanup() {
  kill "$status_watcher" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

tail -n +1 -F "$LOG_FILE" "$SUMMARY_FILE"
