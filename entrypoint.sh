#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/pzagent
export WORKSPACE=${WORKSPACE:-/workspace}
export TZ=${TZ:-Europe/Berlin}

RUNTIME_DIR=/home/pzagent/.config/hermes-worker
RUNTIME_ENV="$RUNTIME_DIR/runtime.env"
SSH_ENV=/home/pzagent/.ssh/environment

mkdir -p /run/sshd /var/run/sshd /home/pzagent/.ssh /home/pzagent/.config /home/pzagent/.config/opencode /home/pzagent/.local/share/opencode "$RUNTIME_DIR" "$WORKSPACE" "$WORKSPACE/delegations"
chown pzagent:pzagent /home/pzagent /home/pzagent/.ssh /home/pzagent/.config /home/pzagent/.config/opencode /home/pzagent/.local /home/pzagent/.local/share /home/pzagent/.local/share/opencode "$RUNTIME_DIR" || true
chmod 700 /home/pzagent/.ssh || true

cat > "$RUNTIME_ENV" <<EOF
# Generated at container start by /entrypoint.sh
# shellcheck shell=bash
export GITHUB_TOKEN=$(printf '%q' "${GITHUB_TOKEN:-}")
export TZ=$(printf '%q' "$TZ")
export WORKSPACE=$(printf '%q' "$WORKSPACE")
export HOME=/home/pzagent
EOF
chown pzagent:pzagent "$RUNTIME_ENV"
chmod 600 "$RUNTIME_ENV"

# Make variables available to SSH sessions too (including non-interactive `ssh host 'cmd'`).
cat > "$SSH_ENV" <<EOF
GITHUB_TOKEN=${GITHUB_TOKEN:-}
TZ=$TZ
WORKSPACE=$WORKSPACE
HOME=/home/pzagent
EOF
chown pzagent:pzagent "$SSH_ENV"
chmod 600 "$SSH_ENV"

if [[ ! -f /home/pzagent/.ssh/authorized_keys ]]; then
  echo "ERROR: /home/pzagent/.ssh/authorized_keys is missing. Mount ~/.pzagent/authorized_keys read-only." >&2
  exit 64
fi
if chmod 600 /home/pzagent/.ssh/authorized_keys 2>/dev/null; then
  :
else
  mode=$(stat -c '%a' /home/pzagent/.ssh/authorized_keys 2>/dev/null || echo unknown)
  owner=$(stat -c '%u:%g' /home/pzagent/.ssh/authorized_keys 2>/dev/null || echo unknown)
  if [[ "$mode" != "600" && "$mode" != "400" ]]; then
    echo "WARNING: authorized_keys is read-only and mode is $mode (owner $owner). SSH StrictModes may reject it; fix host file permissions to 600 and owner UID:GID 1000:1000." >&2
  fi
fi

if [[ -f /home/pzagent/.local/share/opencode/auth.json ]]; then
  echo "OpenCode auth.json mounted." >&2
  if [[ -w /home/pzagent/.local/share/opencode/auth.json ]]; then
    echo "OpenCode auth.json is writable for token refresh." >&2
  else
    echo "WARNING: OpenCode auth.json is not writable. OAuth token refresh may fail; mount auth.json read-write." >&2
  fi
else
  echo "WARNING: OpenCode auth.json is missing at /home/pzagent/.local/share/opencode/auth.json." >&2
fi

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  install -d -m 700 -o pzagent -g pzagent /home/pzagent/.config/gh
  # gh automatically honors GITHUB_TOKEN; do not persist it unless the user chooses to.
else
  echo "WARNING: GITHUB_TOKEN is not set. GitHub PR creation may fail." >&2
fi

/usr/local/bin/bootstrap-worker

# Validate sshd config before replacing the process.
/usr/sbin/sshd -t
exec "$@"
