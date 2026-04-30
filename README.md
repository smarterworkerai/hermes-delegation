# Hermes Delegation Worker

Always-on SSH-accessible OpenCode worker container for Hermes orchestration.

## Quick start

```bash
mkdir -p ~/.pzagent ~/pzagent_work
install -m 600 /path/to/authorized_keys ~/.pzagent/authorized_keys
cat > ~/.pzagent/.worker-env <<'EOF'
GITHUB_TOKEN=your-token
TZ=Europe/Berlin
WORKSPACE=/workspace
EOF
chmod 600 ~/.pzagent/.worker-env
sudo chown -R 1000:1000 ~/pzagent_work

docker compose up -d --build
ssh -p 2022 pzagent@<host> 'echo connected && pwd && git config --global --list'
```

See `docs/worker-runtime.md`, `docs/handoff-format.md`, and `docs/troubleshooting.md` for details. Install the Hermes skill from `skills/start-delegation/` into `~/.hermes/skills/autonomous-ai-agents/start-delegation/` or keep it in this project as operational documentation.
