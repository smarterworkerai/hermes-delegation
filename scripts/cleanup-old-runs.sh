#!/usr/bin/env bash
set -euo pipefail

KEEP=${1:-20}
ROOT=${2:-/workspace/delegations}
[[ "$KEEP" =~ ^[0-9]+$ ]] || { echo "KEEP must be numeric" >&2; exit 64; }
[[ -d "$ROOT" ]] || exit 0

mapfile -t done_runs < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
count=0
for run in "${done_runs[@]}"; do
  state=$(jq -r '.state // "unknown"' "$run/status.json" 2>/dev/null || echo unknown)
  case "$state" in
    running|ready|created|correction_requested|failed) continue ;;
  esac
  count=$((count+1))
  if (( count > KEEP )); then
    echo "Would remove completed run: $run"
  fi
done

echo "Dry-run only. Remove explicitly after review: rm -rf /workspace/delegations/<run-id>"
