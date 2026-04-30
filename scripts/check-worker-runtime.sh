#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ENV=/home/pzagent/.config/hermes-worker/runtime.env

if [[ ! -r "$RUNTIME_ENV" ]]; then
  echo "missing runtime env: $RUNTIME_ENV" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$RUNTIME_ENV"

echo "runtime_env=$RUNTIME_ENV"
echo "github_token=${GITHUB_TOKEN:+set}"
echo "tz=${TZ:-}"
echo "workspace=${WORKSPACE:-}"
echo "source_root=${SOURCE_ROOT:-}"
if [[ -n "${SOURCE_ROOT:-}" ]]; then
  test -d "$SOURCE_ROOT" && test -w "$SOURCE_ROOT" && echo "source_root_writable=yes" || echo "source_root_writable=no"
fi
