#!/usr/bin/env bash
# Expected host tools: bash, git, docker (with `docker compose`), date.
# Manual worker update flow: stop container, remember old image id, pull, rebuild, start, remove old image.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

resolve_repo_dir() {
  if [[ -n "${REPO_DIR:-}" ]]; then
    printf '%s\n' "$REPO_DIR"
    return 0
  fi

  if [[ -f "$PWD/docker-compose.yml" ]]; then
    printf '%s\n' "$PWD"
    return 0
  fi

  if git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$PWD" rev-parse --show-toplevel
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    printf '%s\n' "$SCRIPT_DIR"
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/../docker-compose.yml" ]]; then
    (
      cd -- "$SCRIPT_DIR/.."
      pwd
    )
    return 0
  fi

  printf 'Could not determine REPO_DIR automatically. Run from the repo checkout or set REPO_DIR=/path/to/hermes-delegation.\n' >&2
  return 1
}

REPO_DIR=$(resolve_repo_dir)
COMPOSE_FILE=${COMPOSE_FILE:-$REPO_DIR/docker-compose.yml}
SERVICE_NAME=${SERVICE_NAME:-hermes-worker}
CONTAINER_NAME=${CONTAINER_NAME:-hermes-delegation-worker}
IMAGE_REF=${IMAGE_REF:-hermes-delegation-worker:latest}
DRY_RUN=${DRY_RUN:-0}

usage() {
  cat <<'EOF'
Usage: manual-update-worker.sh

Preferred locations:
  - /workspace/manual-update-worker.sh inside the worker workspace
  - ~/pzagent_work/manual-update-worker.sh on the host via the workspace mount

Environment overrides:
  REPO_DIR        Host checkout of the hermes-delegation repo. If omitted, the script
                  tries the current working directory, the current git repo root, then
                  the script directory and its parent.
  COMPOSE_FILE    Compose file to use (default: $REPO_DIR/docker-compose.yml).
  SERVICE_NAME    Compose service name (default: hermes-worker).
  CONTAINER_NAME  Docker container name (default: hermes-delegation-worker).
  IMAGE_REF       Fallback image reference if the container does not exist.
  DRY_RUN=1       Log commands but do not execute git/docker mutations.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

note() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '[manual-update-worker] %s %s\n' "$ts" "$*" >&2
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

resolve_previous_image_id() {
  local image_id

  image_id=$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}' 2>/dev/null || true)
  if [[ -n "$image_id" ]]; then
    printf '%s\n' "$image_id"
    return 0
  fi

  image_id=$(docker image inspect "$IMAGE_REF" --format '{{.Id}}' 2>/dev/null || true)
  if [[ -n "$image_id" ]]; then
    printf '%s\n' "$image_id"
    return 0
  fi

  return 0
}

cleanup_old_image_if_safe() {
  local previous_image_id=${1:-}
  local current_image_id=${2:-}

  if [[ -z "$previous_image_id" ]]; then
    note "no previous image id found; skipping old image cleanup"
    return 0
  fi

  if [[ "$previous_image_id" == "$current_image_id" ]]; then
    note "image id unchanged; skipping explicit old image removal"
    return 0
  fi

  note "attempting to remove previous worker image by id: $previous_image_id"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  docker image rm "$previous_image_id" >/dev/null 2>&1 || note "previous image already gone or still referenced: $previous_image_id"
}

main() {
  local previous_image_id current_image_id

  previous_image_id=$(resolve_previous_image_id)
  if [[ -n "$previous_image_id" ]]; then
    note "previous image id: $previous_image_id"
  else
    note "previous image id not found before update"
  fi

  compose_cmd stop "$SERVICE_NAME"
  run_cmd git -C "$REPO_DIR" pull --ff-only
  compose_cmd build "$SERVICE_NAME"
  compose_cmd up -d "$SERVICE_NAME"

  if [[ "$DRY_RUN" == "1" ]]; then
    current_image_id="dry-run-current-image-id"
  else
    current_image_id=$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}' 2>/dev/null || true)
  fi

  if [[ -n "$current_image_id" ]]; then
    note "current image id: $current_image_id"
  else
    note "current image id not found after update"
  fi

  cleanup_old_image_if_safe "$previous_image_id" "$current_image_id"
  note "manual worker update completed"
}

main
