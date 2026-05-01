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

## Host-side update watchdog

If a worker task changes runtime/container code and the running worker must be refreshed, signal it from inside the mounted workspace:

```bash
touch /workspace/update_available
```

That same marker appears on the host as `~/pzagent_work/update_available`.
A host-side watchdog can react to it and refresh the worker from the repo checkout:

```bash
bash scripts/worker-update-watchdog.sh
```

Default behavior when the marker appears:

1. `git -C <repo> pull --ff-only`
2. `docker compose up -d --build --force-recreate`
3. remove the previous worker image if it is no longer used
4. `docker image prune -f`
5. remove `update_available`

State files written under `~/pzagent_work`:

- `update_in_progress`
- `update_failed`
- `worker-update-watchdog.log`

For one-shot processing during testing or from cron/systemd wrappers:

```bash
RUN_ONCE=1 bash scripts/worker-update-watchdog.sh
```

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
