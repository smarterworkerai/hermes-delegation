#!/usr/bin/env bash
set -euo pipefail

RUN_DIR=${1:-}
[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || { echo "Usage: collect-results <run-dir>" >&2; exit 64; }

printf '# Delegation result: %s\n\n' "$(basename "$RUN_DIR")"
printf '## status.json\n\n```json\n'
cat "$RUN_DIR/status.json" 2>/dev/null || true
printf '\n```\n\n'

for f in 12-output-summary.md 10-worker-log.md 11-commands.md; do
  if [[ -f "$RUN_DIR/$f" ]]; then
    printf '## %s\n\n' "$f"
    cat "$RUN_DIR/$f"
    printf '\n\n'
  fi
done

printf '## result artifacts\n\n'
find "$RUN_DIR/result" -maxdepth 3 -type f -printf '- %p\n' 2>/dev/null | sort || true
if [[ -f "$RUN_DIR/result/notes/pr-url.txt" ]]; then
  printf '\n## PR/MR URL\n\n%s\n' "$(cat "$RUN_DIR/result/notes/pr-url.txt")"
fi
