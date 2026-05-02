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

## High-Level Overview

This section explains **what this project is for** and **how to use it** at a high level.

It uses the PlantUML proxy rendering approach (`plantuml-markdown` style), so diagrams are directly visible on GitHub.

### What problem this solves

`hermes-delegation` provides an always-on SSH worker (`pzagent`) that Hermes can delegate implementation tasks to.

Core goals:

- keep delegation execution isolated from the orchestrator host
- standardize handoff format and run artifacts
- make delegated runs observable/reviewable
- keep repository work under `/workspace/source/<project-name>`
- keep run logs and outputs under `/workspace/delegations/<run-id>`

### Where this fits in the workflow

![System Context](http://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/smarterworkerai/hermes-delegation/feature/plantuml-high-level-docs/docs/diagrams/system-context.puml)

### Typical runtime components

![Runtime Components](http://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/smarterworkerai/hermes-delegation/feature/plantuml-high-level-docs/docs/diagrams/runtime-components.puml)

### How to use it (operator flow)

![Operator Flow](http://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/smarterworkerai/hermes-delegation/feature/plantuml-high-level-docs/docs/diagrams/operator-flow.puml)

### Minimal usage checklist

1. Set host prerequisites (`~/.pzagent`, `~/pzagent_work/source`, `.worker-env`).
2. Start worker (`docker compose up -d --build`).
3. Verify connectivity (`ssh -p 2022 pzagent@<host>`, `check-worker-runtime`).
4. Run delegation from Hermes (`start-delegation <host> <model>`).
5. Review run outputs in `/workspace/delegations/<run-id>/`:
   - `status.json`
   - `11-commands.md`
   - `12-output-summary.md`
   - `result/` artifacts

### Editing diagrams

- Source files live under `docs/diagrams/*.puml`
- GitHub-rendered images in this doc resolve through PlantUML proxy + `raw.githubusercontent.com`
- `cache=no` is used so the latest committed `.puml` is rendered

### Reading order for deeper detail

- Runtime specifics: `docs/worker-runtime.md`
- Handoff structure: `docs/handoff-format.md`
- Failure handling: `docs/troubleshooting.md`

## Manual worker refresh

If worker/container/runtime code changes, refresh the worker manually from the host repo checkout:

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

This keeps worker refresh explicit and avoids background auto-update behavior.

See `docs/worker-runtime.md`, `docs/handoff-format.md`, and `docs/troubleshooting.md` for details. Install the Hermes skill from `skills/start-delegation/` into `~/.hermes/skills/autonomous-ai-agents/start-delegation/` or keep it in this project as operational documentation.

## Documentation

- [High-level overview with PlantUML diagrams](docs/high-level-overview.md)
