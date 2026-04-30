# Worker runtime

## Runtime model

The worker is an always-on Docker Compose service exposing SSH on host port `2022` and running as user `pzagent` with UID/GID `1000:1000` and home `/home/pzagent`.

## Image contents

The image is based on `debian:13-slim` and includes: OpenSSH server, OpenCode (`opencode`), git, GitHub CLI (`gh`), tmux, jq, ripgrep, Python 3, Node.js/npm, and common archive/editor tools.

## Host prerequisites

```bash
mkdir -p ~/.pzagent ~/pzagent_work
install -m 600 /path/to/authorized_keys ~/.pzagent/authorized_keys
sudo chown -R 1000:1000 ~/pzagent_work
cat > ~/.pzagent/.worker-env <<'EOF'
GITHUB_TOKEN=***
TZ=Europe/Berlin
WORKSPACE=/workspace
EOF
chmod 600 ~/.pzagent/.worker-env
test -f ~/.local/share/opencode/auth.json && echo opencode-auth-ok
```

## Mount table

| Host path | Container path | Mode | Purpose |
|---|---|---:|---|
| `~/.pzagent/authorized_keys` | `/home/pzagent/.ssh/authorized_keys` | ro | SSH login keys |
| `~/.local/share/opencode/auth.json` | `/home/pzagent/.local/share/opencode/auth.json` | ro | OpenCode auth |
| `~/pzagent_work` | `/workspace` | rw | Repos and delegation artifacts |
| `~/.pzagent/.worker-env` | env file | n/a | `GITHUB_TOKEN`, `TZ`, `WORKSPACE` |

## Build and run

```bash
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 hermes-worker
```

## Smoke checks

```bash
ssh -p 2022 pzagent@<host> 'echo connected'
ssh -p 2022 pzagent@<host> 'pwd; touch /workspace/.write-test && rm /workspace/.write-test && echo workspace-ok'
ssh -p 2022 pzagent@<host> 'opencode --help >/dev/null && echo opencode-ok'
ssh -p 2022 pzagent@<host> 'test -f ~/.local/share/opencode/auth.json && echo opencode-auth-ok'
ssh -p 2022 pzagent@<host> 'test -n "$GITHUB_TOKEN" && echo github-token-ok'
ssh -p 2022 pzagent@<host> 'git config --global user.name && git config --global user.email'
```

Expected git identity:

```text
Hermes Agent
smarterworkerai@protonmail.com
```

## Repository placement

When a delegated task needs a repository, clone it directly under `/workspace/<project-name>`. Do not use an extra `/workspace/repos` layer for the first implementation.
