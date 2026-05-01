# Hermes Delegation Worker

Always-on SSH-accessible OpenCode worker container for Hermes orchestration.

## Quick start

```bash
mkdir -p ~/.pzagent ~/pzagent_work/source
install -m 600 /path/to/authorized_keys ~/.pzagent/authorized_keys
cat > ~/.pzagent/.worker-env <<'EOF'
GITHUB_TOKEN=***
TZ=Europe/Berlin
WORKSPACE=/workspace
SOURCE_ROOT=/workspace/source
EOF
chmod 600 ~/.pzagent/.worker-env
sudo chown -R 1000:1000 ~/pzagent_work
docker compose up -d --build
ssh -p 2022 pzagent@<host> 'echo connected && pwd && git config --global --list'
ssh -p 2022 pzagent@<host> 'check-worker-runtime'
```

## Validated smoke test

The implementation was validated end-to-end with a real `start-delegation` run against the always-on SSH worker.

Validated run summary:

- host: `127.0.0.1`
- model: `openai/gpt-5.5`
- run id: `smoke-20260430-161200-start-delegation`
- final state: `done`
- result: `exit_code=0`
- correction rounds: `0`

Recommended validation flow after setup:

```bash
chmod 600 ~/.ssh/<worker-key>
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'echo CONNECTED && whoami && pwd'
start-delegation <host> openai/gpt-5.5
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'ls -td /workspace/delegations/* | head -1'
ssh -i ~/.ssh/<worker-key> -p 2022 pzagent@<host> 'jq . /workspace/delegations/<run-id>/status.json'
```

Expected success indicators:

- SSH login succeeds as `pzagent`
- the run directory is created under `/workspace/delegations/<run-id>`
- source repositories are cloned under `/workspace/source/<project-name>`
- `status.json` reaches `state: done`
- the run produces `11-commands.md`, `12-output-summary.md`, and `result/notes/smoke-proof.txt`

## Worker self-update signal

When a delegated task changes worker/runtime code and the host must rebuild the worker image, the orchestrator or a container-side process can create an empty marker file in the mounted workspace:

```bash
touch /workspace/update_available
```

Because `~/pzagent_work` is mounted to `/workspace`, that marker is also visible on the host as:

```bash
~/pzagent_work/update_available
```

Run the host-side watchdog from the repo checkout:

```bash
bash scripts/worker-update-watchdog.sh
```

What it does when the marker appears:

1. `git -C <repo> pull --ff-only`
2. `docker compose up -d --build --force-recreate`
3. remove the previous worker image if it is no longer in use
4. `docker image prune -f`
5. remove `update_available`

Useful files in `~/pzagent_work`:

- `update_available` — requested rebuild/recreate
- `update_in_progress` — watchdog is processing the update
- `update_failed` — last update attempt failed; marker is left in place
- `worker-update-watchdog.log` — append-only watchdog log

See `docs/worker-runtime.md`, `docs/handoff-format.md`, and `docs/troubleshooting.md` for details. Install the Hermes skill from `skills/start-delegation/` into `~/.hermes/skills/autonomous-ai-agents/start-delegation/` or keep it in this project as operational documentation.
