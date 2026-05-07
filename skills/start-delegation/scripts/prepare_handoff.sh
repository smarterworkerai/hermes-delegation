#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: prepare_handoff.sh <local-dir> <run-id> <host> <model> <task-brief-file> [acceptance-file]

Creates the standard markdown handoff bundle locally. Upload it with scp/rsync to:
  pzagent@<host>:/workspace/delegations/<run-id>/
EOF
}
[[ $# -ge 5 ]] || { usage; exit 64; }
LOCAL_DIR=$1
RUN_ID=$2
HOST=$3
MODEL=$4
TASK_FILE=$5
ACCEPTANCE_FILE=${6:-}
mkdir -p "$LOCAL_DIR/result/patches" "$LOCAL_DIR/result/notes" "$LOCAL_DIR/result/artifacts"
cp "$TASK_FILE" "$LOCAL_DIR/00-task-brief.md"
cat > "$LOCAL_DIR/01-environment.md" <<EOF
# Environment

- Worker host: $HOST
- Worker SSH port: 2022
- Worker user: pzagent
- Model: $MODEL
- Workspace: /workspace
- Delegation run directory: /workspace/delegations/$RUN_ID
- Repository checkout rule: clone directly under /workspace/source/<project-name>
EOF
cat > "$LOCAL_DIR/02-constraints.md" <<'EOF'
# Constraints

- Use OpenCode only.
- Keep all writes inside /workspace unless explicitly required by the task.
- Prefer a PR/MR as the primary implementation artifact for code changes.
- Do not invent credentials. Use only mounted/authenticated tools.
- Record important commands in 11-commands.md.
EOF
if [[ -n "$ACCEPTANCE_FILE" && -f "$ACCEPTANCE_FILE" ]]; then
  cp "$ACCEPTANCE_FILE" "$LOCAL_DIR/03-acceptance-criteria.md"
else
  cat > "$LOCAL_DIR/03-acceptance-criteria.md" <<'EOF'
# Acceptance criteria

- The requested task is completed or blockers are clearly reported.
- Verification commands and results are documented.
- PR/MR URL is provided when code changes are made.
- Final free-form summary is written to 12-output-summary.md.
EOF
fi
cat > "$LOCAL_DIR/04-input-artifacts.md" <<'EOF'
# Input artifacts

No additional artifacts were attached by prepare_handoff.sh. The orchestrator may add paths, URLs, or copied files here before launch.
EOF
cat > "$LOCAL_DIR/status.json" <<EOF
{
  "run_id": "$RUN_ID",
  "host": "$HOST",
  "model": "$MODEL",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "started_at": null,
  "completed_at": null,
  "state": "created",
  "result": null,
  "correction_rounds": 0
}
EOF
touch "$LOCAL_DIR/10-worker-log.md" "$LOCAL_DIR/11-commands.md" "$LOCAL_DIR/12-output-summary.md"
echo "$LOCAL_DIR"
