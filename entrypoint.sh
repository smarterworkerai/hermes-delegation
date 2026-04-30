#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/pzagent
export WORKSPACE=${WORKSPACE:-/workspace}
export TZ=${TZ:-Europe/Berlin}

mkdir -p /run/sshd /var/run/sshd /home/pzagent/.ssh /home/pzagent/.local/share/opencode "$WORKSPACE" "$WORKSPACE/delegations"
chown pzagent:pzagent /home/pzagent /home/pzagent/.ssh /home/pzagent/.local /home/pzagent/.local/share /home/pzagent/.local/share/opencode || true
chmod 700 /home/pzagent/.ssh || true

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
