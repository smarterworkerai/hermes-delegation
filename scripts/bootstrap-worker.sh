#!/usr/bin/env bash
set -euo pipefail

run_as_pzagent() {
  su -s /bin/bash - pzagent -c "$*"
}

mkdir -p /workspace/delegations /home/pzagent/.config/opencode
chown pzagent:pzagent /workspace /workspace/delegations /home/pzagent/.config /home/pzagent/.config/opencode 2>/dev/null || true

run_as_pzagent 'git config --global user.name "Hermes Agent"'
run_as_pzagent 'git config --global user.email "smarterworkerai@protonmail.com"'
run_as_pzagent 'git config --global init.defaultBranch main'
run_as_pzagent 'git config --global --add safe.directory /workspace 2>/dev/null || true'

cat >&2 <<EOF
Hermes delegation worker bootstrap complete.
user: $(id pzagent)
workspace: /workspace
opencode: $(command -v opencode || echo missing)
gh: $(command -v gh || echo missing)
EOF
