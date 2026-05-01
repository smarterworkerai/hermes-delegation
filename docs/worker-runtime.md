# Worker runtime

## Runtime model

The worker is an always-on Docker Compose service exposing SSH on host port `2022` and running as user `pzagent` with UID/GID `1000:1000` and home `/home/pzagent`.

## Image contents

The image is based on `debian:13-slim` and includes: OpenSSH server, OpenCode (`opencode`), git, GitHub CLI (`gh`), tmux, jq, ripgrep, Python 3, Node.js/npm, and common archive/editor tools.

## Host prerequisites

```bash
mkdir -p ~/.pzagent ~/pzagent_work/source
install -m 600 /path/to/authorized_keys ~/.pzagent/authorized_keys
sudo chown -R 1000:1000 ~/pzagent_work
cat > ~/.pzagent/.worker-env <<'EOF'
GITHUB_TOKEN=***
TZ=Europe/Berlin
WORKSPACE=/workspace
SOURCE_ROOT=/workspace/source
EOF
chmod 600 ~/.pzagent/.worker-env
test -f ~/.local/share/opencode/auth.json && test -w ~/.local/share/opencode/auth.json && echo opencode-auth-rw-ok
```

## Mount table

| Host path | Container path | Mode | Purpose |
|---|---|---:|---|
| `~/.pzagent/authorized_keys` | `/home/pzagent/.ssh/authorized_keys` | ro | SSH login keys |
| `~/.local/share/opencode/auth.json` | `/home/pzagent/.local/share/opencode/auth.json` | rw | OpenCode auth; writable so OAuth refresh tokens can be rotated |
| `~/pzagent_work` | `/workspace` | rw | Delegation artifacts plus `source/` checkout root |
| `~/pzagent_work/source` | `/workspace/source` | rw | Repository checkout root |
| `~/.pzagent/.worker-env` | env file | n/a | `GITHUB_TOKEN`, `TZ`, `WORKSPACE`, `SOURCE_ROOT` |

## Build and run

```bash
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 hermes-worker
```

## Manual worker refresh

If worker/container/runtime code changes and the running worker should be refreshed, do it manually from the host repo checkout:

```bash
bash /workspace/manual-update-worker.sh
```

What the script does:

1. stop the worker container
2. remember the previous worker image id
3. `git pull --ff-only`
4. rebuild the worker image
5. start the worker again
6. remove the previous worker image by id if it is no longer referenced

This is the preferred mode for this setup: refresh stays explicit, and there is no background watchdog or marker-based auto update flow.

## Smoke checks

```bash
ssh -p 2022 pzagent@<host> 'echo connected'
ssh -p 2022 pzagent@<host> 'pwd; touch /workspace/.write-test && rm /workspace/.write-test && echo workspace-ok'
ssh -p 2022 pzagent@<host> 'touch /workspace/source/.write-test && rm /workspace/source/.write-test && echo source-root-ok'
ssh -p 2022 pzagent@<host> 'opencode --help >/dev/null && echo opencode-ok'
ssh -p 2022 pzagent@<host> 'test -f ~/.local/share/opencode/auth.json && test -w ~/.local/share/opencode/auth.json && echo opencode-auth-rw-ok'
ssh -p 2022 pzagent@<host> 'check-worker-runtime'
ssh -p 2022 pzagent@<host> 'test -n "$GITHUB_TOKEN" && echo github-token-ok'
ssh -p 2022 pzagent@<host> 'git config --global user.name && git config --global user.email'
```

Expected git identity:

```text
Hermes Agent
smarterworkerai@protonmail.com
```

## Validated end-to-end `start-delegation` smoke test

A real end-to-end validation was run successfully against the worker:

- host: `127.0.0.1`
- model: `openai/gpt-5.5`
- run id: `smoke-20260430-161200-start-delegation`
- final `status.json` state: `done`
- final result: `exit_code=0`
- correction rounds: `0`

Recommended operator workflow:

```bash
chmod 600 ~/.ssh/<worker-key>
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'echo CONNECTED && whoami && pwd'
start-delegation <host> openai/gpt-5.5
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'ls -td /workspace/delegations/* | head -1'
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'jq . /workspace/delegations/<run-id>/status.json'
```

Success criteria:

- the worker accepts SSH key login as `pzagent`
- the delegation creates `/workspace/delegations/<run-id>/`
- source repositories are cloned under `/workspace/source/<project-name>`
- `status.json` transitions to `done`
- the run emits:
  - `11-commands.md`
  - `12-output-summary.md`
  - `result/notes/smoke-proof.txt`

Observed proof from the validated run:

- `whoami` = `pzagent`
- OpenCode launch `pwd` = `/workspace/source`
- `opencode --version` = `1.14.30`
- `gh --version | head -1` = `gh version 2.92.0 (2026-04-28)`

## Repository placement

When a delegated task needs a repository, clone it directly under `/workspace/source/<project-name>`. Keep `/workspace/delegations` reserved for handoff bundles, logs, and results.
