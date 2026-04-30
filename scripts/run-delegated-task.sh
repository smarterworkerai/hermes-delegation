#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ENV=/home/pzagent/.config/hermes-worker/runtime.env
if [[ -r "$RUNTIME_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"
fi

usage() {
  cat >&2 <<'EOF'
Usage: run-delegated-task <run-dir> <model> [correction-file]

Launches OpenCode in a detached tmux session for the prepared handoff directory.
The model is passed to OpenCode unchanged. No OpenRouter defaulting is performed.
EOF
}

[[ $# -ge 2 ]] || { usage; exit 64; }
RUN_DIR=$1
MODEL=$2
CORRECTION_FILE=${3:-}
RUN_ID=$(basename "$RUN_DIR")
SESSION="delegation-${RUN_ID//[^A-Za-z0-9_.-]/-}"
HOST_NAME=$(hostname -f 2>/dev/null || hostname)

mkdir -p "$RUN_DIR/result/patches" "$RUN_DIR/result/notes" "$RUN_DIR/result/artifacts"
touch "$RUN_DIR/10-worker-log.md" "$RUN_DIR/11-commands.md" "$RUN_DIR/12-output-summary.md"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
json_update() {
  local state=$1 result=${2:-null}
  local tmp
  tmp=$(mktemp)
  jq --arg state "$state" --arg ts "$(now_utc)" --argjson result "$result" \
    '.state=$state | if ($state=="running") then .started_at=$ts elif ($state=="done" or $state=="failed" or $state=="review") then .completed_at=$ts else . end | .result=$result' \
    "$RUN_DIR/status.json" > "$tmp" && mv "$tmp" "$RUN_DIR/status.json"
}

if [[ ! -f "$RUN_DIR/status.json" ]]; then
  cat > "$RUN_DIR/status.json" <<EOF
{
  "run_id": "$RUN_ID",
  "host": "$HOST_NAME",
  "model": "$MODEL",
  "created_at": "$(now_utc)",
  "started_at": null,
  "completed_at": null,
  "state": "created",
  "result": null,
  "correction_rounds": 0
}
EOF
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Existing tmux session $SESSION is already present." >&2
  exit 65
fi

PROMPT_FILE="$RUN_DIR/.opencode-prompt.md"
{
  echo "# Delegated task"
  echo
  echo "You are an always-on OpenCode worker running inside the Hermes delegation container."
  echo "Use /workspace for repositories. Clone repositories directly under /workspace/<project-name>."
  echo "Make the primary deliverable a GitHub PR/MR when the task involves code changes."
  echo "Write a clear free-form final report to $RUN_DIR/12-output-summary.md."
  echo "If you create a PR/MR, write its URL to $RUN_DIR/result/notes/pr-url.txt."
  echo "Record important commands in $RUN_DIR/11-commands.md."
  echo
  for f in 00-task-brief.md 01-environment.md 02-constraints.md 03-acceptance-criteria.md 04-input-artifacts.md; do
    if [[ -f "$RUN_DIR/$f" ]]; then
      echo
      echo "---"
      echo
      cat "$RUN_DIR/$f"
    fi
  done
  if [[ -n "$CORRECTION_FILE" && -f "$CORRECTION_FILE" ]]; then
    echo
    echo "---"
    echo
    echo "# Correction request"
    cat "$CORRECTION_FILE"
  fi
} > "$PROMPT_FILE"

cat >> "$RUN_DIR/11-commands.md" <<EOF

## Launch $(now_utc)

```bash
cd /workspace
source /home/pzagent/.config/hermes-worker/runtime.env
opencode run --model '$MODEL' "\$(cat '$PROMPT_FILE')"
```
EOF

RUNNER="$RUN_DIR/.tmux-runner.sh"
cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
RUN_DIR=$1
MODEL=$2
PROMPT_FILE=$3
RUNTIME_ENV=/home/pzagent/.config/hermes-worker/runtime.env
if [[ -r "$RUNTIME_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"
fi
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
update_state() {
  local state=$1 result=${2:-null}
  local tmp
  tmp=$(mktemp)
  jq --arg state "$state" --arg ts "$(now_utc)" --argjson result "$result" \
    '.state=$state | if ($state=="running") then .started_at=$ts elif ($state=="done" or $state=="failed") then .completed_at=$ts else . end | .result=$result' \
    "$RUN_DIR/status.json" > "$tmp" && mv "$tmp" "$RUN_DIR/status.json"
}
{
  echo "# Worker log"
  echo
  echo "Started: $(now_utc)"
  echo "Model: $MODEL"
  echo "Run dir: $RUN_DIR"
  echo
} >> "$RUN_DIR/10-worker-log.md"
update_state running null
set +e
cd /workspace
opencode run --model "$MODEL" "$(cat "$PROMPT_FILE")" 2>&1 | tee -a "$RUN_DIR/10-worker-log.md" > "$RUN_DIR/result/artifacts/opencode-output.txt"
rc=${PIPESTATUS[0]}
set -e
if [[ $rc -eq 0 ]]; then
  if [[ ! -s "$RUN_DIR/12-output-summary.md" ]]; then
    cp "$RUN_DIR/result/artifacts/opencode-output.txt" "$RUN_DIR/12-output-summary.md"
  fi
  update_state done '{"exit_code":0}'
  echo "Completed: $(now_utc)" >> "$RUN_DIR/10-worker-log.md"
else
  {
    echo "# Delegated task failed"
    echo
    echo "OpenCode exited with code $rc. See 10-worker-log.md and result/artifacts/opencode-output.txt."
  } > "$RUN_DIR/12-output-summary.md"
  update_state failed "{\"exit_code\":$rc}"
  echo "Failed: $(now_utc), exit_code=$rc" >> "$RUN_DIR/10-worker-log.md"
fi
EOF
chmod +x "$RUNNER"
json_update ready null

tmux new-session -d -s "$SESSION" "$RUNNER" "$RUN_DIR" "$MODEL" "$PROMPT_FILE"
echo "launched tmux session: $SESSION"
echo "$SESSION" > "$RUN_DIR/result/notes/tmux-session.txt"
