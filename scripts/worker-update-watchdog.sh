#!/usr/bin/env bash
# Expected host tools: bash, git, docker (with `docker compose`), mkdir, rm, touch, date.
# Watches a workspace marker file and rebuilds/recreates the worker from the host repo.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}
WORKSPACE_DIR=${WORKSPACE_DIR:-$HOME/pzagent_work}
UPDATE_MARKER=${UPDATE_MARKER:-$WORKSPACE_DIR/update_available}
UPDATE_IN_PROGRESS=${UPDATE_IN_PROGRESS:-$WORKSPACE_DIR/update_in_progress}
UPDATE_FAILED=${UPDATE_FAILED:-$WORKSPACE_DIR/update_failed}
LOG_FILE=${LOG_FILE:-$WORKSPACE_DIR/worker-update-watchdog.log}
LOCK_DIR=${LOCK_DIR:-$WORKSPACE_DIR/.worker-update-watchdog.lock}
COMPOSE_FILE=${COMPOSE_FILE:-$REPO_DIR/docker-compose.yml}
CONTAINER_NAME=${CONTAINER_NAME:-hermes-delegation-worker}
IMAGE_NAME=${IMAGE_NAME:-hermes-delegation-worker:latest}
POLL_INTERVAL=${POLL_INTERVAL:-5}
RUN_ONCE=${RUN_ONCE:-0}
DRY_RUN=${DRY_RUN:-0}

usage() {
  cat <<'EOF'
Usage: worker-update-watchdog.sh

Environment overrides:
  REPO_DIR            Host checkout of the hermes-delegation repo.
  WORKSPACE_DIR       Host path mounted into the worker as /workspace.
  UPDATE_MARKER       Marker file created by the orchestrator/container.
  UPDATE_IN_PROGRESS  File touched while rebuild/recreate is running.
  UPDATE_FAILED       File touched when rebuild/recreate fails.
  LOG_FILE            Append-only watchdog log file.
  POLL_INTERVAL       Seconds between checks (default: 5).
  RUN_ONCE=1          Process at most one marker event, then exit.
  DRY_RUN=1           Log commands but do not execute git/docker mutations.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$WORKSPACE_DIR"
touch "$LOG_FILE"

note() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '[worker-update-watchdog] %s %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
}

run_cmd() {
  note "+ $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  "$@"
}

compose_cmd() {
  run_cmd docker compose -f "$COMPOSE_FILE" "$@"
}

cleanup_old_image_if_safe() {
  local previous_image_id=${1:-}
  local current_image_id=${2:-}

  if [[ -z "$previous_image_id" ]]; then
    return 0
  fi
  if [[ "$previous_image_id" == "$current_image_id" ]]; then
    note "image id unchanged; skipping explicit old image removal"
    return 0
  fi

  note "attempting to remove previous worker image: $previous_image_id"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  docker image rm "$previous_image_id" >/dev/null 2>&1 || note "previous image already gone or still referenced: $previous_image_id"
}

process_update() {
  local previous_image_id current_image_id

  note "update marker detected: $UPDATE_MARKER"
  rm -f "$UPDATE_FAILED"
  touch "$UPDATE_IN_PROGRESS"

  previous_image_id=$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}' 2>/dev/null || true)

  if ! run_cmd git -C "$REPO_DIR" pull --ff-only; then
    note "git pull failed; leaving marker in place"
    touch "$UPDATE_FAILED"
    rm -f "$UPDATE_IN_PROGRESS"
    return 1
  fi

  if ! compose_cmd up -d --build --force-recreate; then
    note "docker compose rebuild/recreate failed; leaving marker in place"
    touch "$UPDATE_FAILED"
    rm -f "$UPDATE_IN_PROGRESS"
    return 1
  fi

  current_image_id=$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}' 2>/dev/null || true)
  cleanup_old_image_if_safe "$previous_image_id" "$current_image_id"

  if [[ "$DRY_RUN" == "1" ]]; then
    note "+ docker image prune -f"
  else
    docker image prune -f >/dev/null 2>&1 || note "docker image prune returned non-zero"
  fi

  rm -f "$UPDATE_MARKER" "$UPDATE_IN_PROGRESS" "$UPDATE_FAILED"
  note "worker update completed successfully"
  return 0
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
    return 0
  fi
  note "another watchdog instance appears to be running; lock exists at $LOCK_DIR"
  return 1
}

main_loop() {
  acquire_lock || exit 0
  note "watching marker: $UPDATE_MARKER"
  note "repo_dir=$REPO_DIR workspace_dir=$WORKSPACE_DIR compose_file=$COMPOSE_FILE"

  while true; do
    if [[ -e "$UPDATE_MARKER" ]]; then
      process_update || true
      if [[ "$RUN_ONCE" == "1" ]]; then
        break
      fi
    else
      if [[ "$RUN_ONCE" == "1" ]]; then
        break
      fi
    fi
    sleep "$POLL_INTERVAL"
  done
}

main_loop
