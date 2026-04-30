# Hermes Delegation Worker

Always-on SSH-accessible OpenCode worker container for Hermes orchestration.

## Quick start

```bash
mkdir -p ~/.pzagent ~/pzagent_work
install -m 600 /path/to/authorized_keys ~/.pzagent/authorized_keys
cat > ~/.pzagent/.worker-env <<'EOF'
GITHUB_TOKEN=***
TZ=Europe/Berlin
WORKSPACE=/workspace
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
- `status.json` reaches `state: done`
- the run produces `11-commands.md`, `12-output-summary.md`, and `result/notes/smoke-proof.txt`

See `docs/worker-runtime.md`, `docs/handoff-format.md`, and `docs/troubleshooting.md` for details. Install the Hermes skill from `skills/start-delegation/` into `~/.hermes/skills/autonomous-ai-agents/start-delegation/` or keep it in this project as operational documentation.
