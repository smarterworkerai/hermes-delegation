#!/usr/bin/env bash
set -euo pipefail

run_as_pzagent() {
  su -s /bin/bash - pzagent -c "$*"
}

WORKSPACE=${WORKSPACE:-/workspace}
SOURCE_ROOT=${SOURCE_ROOT:-$WORKSPACE/source}
DELEGATIONS_ROOT=${DELEGATIONS_ROOT:-$WORKSPACE/delegations}

mkdir -p "$DELEGATIONS_ROOT" "$SOURCE_ROOT" /home/pzagent/.config/opencode
chown pzagent:pzagent "$WORKSPACE" "$DELEGATIONS_ROOT" "$SOURCE_ROOT" /home/pzagent/.config /home/pzagent/.config/opencode 2>/dev/null || true

install -m 755 /usr/local/bin/follow-delegation "$DELEGATIONS_ROOT/follow-delegation"
chown pzagent:pzagent "$DELEGATIONS_ROOT/follow-delegation" 2>/dev/null || true
install -m 755 /usr/local/bin/manual-update-worker "$WORKSPACE/manual-update-worker.sh"
chown pzagent:pzagent "$WORKSPACE/manual-update-worker.sh" 2>/dev/null || true

run_as_pzagent 'git config --global user.name "Hermes Agent"'
run_as_pzagent 'git config --global user.email "smarterworkerai@protonmail.com"'
run_as_pzagent 'git config --global init.defaultBranch main'
run_as_pzagent "git config --global --add safe.directory $WORKSPACE 2>/dev/null || true"
run_as_pzagent "git config --global --add safe.directory $SOURCE_ROOT 2>/dev/null || true"

cat >&2 <<EOF
Hermes delegation worker bootstrap complete.
user: $(id pzagent)
workspace: $WORKSPACE
source_root: $SOURCE_ROOT
opencode: $(command -v opencode || echo missing)
gh: $(command -v gh || echo missing)
EOF
