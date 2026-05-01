---
name: start-delegation
description: Use when delegating implementation work to the always-on SSH OpenCode worker with `start-delegation <host> <model>`; creates markdown handoff bundles, launches remote tmux/OpenCode jobs, collects artifacts, and performs orchestrator review.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [delegation, opencode, ssh, worker, docker]
    related_skills: [opencode, hermes-agent]
---

# Start Delegation

## Overview

Use this skill when the user says `start-delegation <host> <model>` or asks to hand off coding work to the always-on SSH OpenCode worker. The worker runs as `pzagent`, listens on SSH port `2022`, uses `/workspace` as the writable host bind mount, stores run artifacts under `/workspace/delegations/<run-id>/`, and keeps source checkouts under `/workspace/source/<project-name>`.

The orchestrator remains responsible for context preparation, launch, polling, medium-depth review, correction rounds for weak output, and the final user-facing summary.

## Invocation

```text
start-delegation <host> <model>
```

Examples:

```text
start-delegation 192.168.1.50 openai/gpt-5.4
start-delegation worker.local openrouter/claude4.6
```

- `<host>` is a raw IP address or raw hostname.
- `<model>` is an explicit OpenCode provider/model string and is passed through unchanged.
- Do **not** default to OpenRouter. Only use OpenRouter when the model explicitly starts with `openrouter/`.

## Procedure

1. **Parse host/model.** If the user gives a task along with the invocation, use it as the task brief. Otherwise ask for the task brief.
2. **Prerequisite checks:**
   ```bash
   ssh -p 2022 -o BatchMode=yes -o ConnectTimeout=8 pzagent@<host> 'echo connected'
   ssh -p 2022 pzagent@<host> 'test -w /workspace && echo workspace-ok'
   ssh -p 2022 pzagent@<host> 'test -d /workspace/source && test -w /workspace/source && echo source-root-ok'
   ssh -p 2022 pzagent@<host> 'command -v opencode && command -v tmux && command -v gh && command -v jq'
   ssh -p 2022 pzagent@<host> 'test -f ~/.local/share/opencode/auth.json && test -w ~/.local/share/opencode/auth.json && echo opencode-auth-rw-ok'
   ssh -p 2022 pzagent@<host> 'check-worker-runtime'
   ssh -p 2022 pzagent@<host> 'test -n "$GITHUB_TOKEN" && echo github-token-ok'
   ssh -p 2022 pzagent@<host> 'git config --global user.name && git config --global user.email'
   ssh -p 2022 pzagent@<host> 'df -h /workspace'
   ssh -p 2022 pzagent@<host> 'find /workspace/delegations -maxdepth 2 -name status.json -exec jq -r "select(.state==\"running\" or .state==\"ready\") | .run_id" {} + 2>/dev/null || true'
   ```
   If another run is active, show: `Another delegated task is already running on this worker.` Continue only because this skill invocation is explicit.
3. **Create a run id:** `YYYYMMDD-HHMMSS-<task-slug>`.
4. **Create a local handoff directory** using `scripts/prepare_handoff.sh` or equivalent markdown files:
   - `00-task-brief.md`
   - `01-environment.md`
   - `02-constraints.md`
   - `03-acceptance-criteria.md`
   - `04-input-artifacts.md`
   - `status.json`
5. **Upload handoff:**
   ```bash
   ssh -p 2022 pzagent@<host> 'mkdir -p /workspace/delegations/<run-id>'
   scp -P 2022 -r <local-handoff>/* pzagent@<host>:/workspace/delegations/<run-id>/
   ```
6. **Launch worker job:**
   ```bash
   ssh -p 2022 pzagent@<host> 'run-delegated-task /workspace/delegations/<run-id> <model>'
   ```
   The worker launches a detached tmux session and returns immediately.
7. **Poll status:**
   ```bash
   ssh -p 2022 pzagent@<host> 'jq -r .state /workspace/delegations/<run-id>/status.json'
   ```
   Terminal states are `done` and `failed`.
8. **Inspect a live run when requested:**
   ```bash
   ssh -p 2022 pzagent@<host> 'tmux ls'
   ssh -p 2022 pzagent@<host> '/workspace/delegations/follow-delegation <run-id>'
   ssh -p 2022 pzagent@<host> 'tail -n 120 /workspace/delegations/<run-id>/10-worker-log.md'
   ssh -p 2022 pzagent@<host> 'tail -n 120 /workspace/delegations/<run-id>/12-output-summary.md'
   ssh -t -p 2022 pzagent@<host> 'tmux attach -t delegation-<run-id>'
   ```
   Prefer `/workspace/delegations/follow-delegation <run-id>` for live observation. It should wait for the run directory and log files instead of failing if the worker has not started writing yet. In practice, tailing `10-worker-log.md` and `12-output-summary.md` is often more informative than attaching to tmux, because the launcher may tee output into files while the interactive pane appears idle. Use `tmux attach` only when you specifically need the terminal state; detach with `Ctrl-b` then `d` because `Ctrl-c` can stop the worker process.
9. **Request a manual host-side worker refresh when runtime code changes:** If worker image/bootstrap/runtime code, helper scripts, or files expected under `/workspace/delegations` change, the running worker may still be on the old container. In that case, refresh it manually from the host repo checkout:
   ```bash
   bash /workspace/manual-update-worker.sh
   ```
   Do not assume there is a watchdog or marker-based auto-update flow. When reviewing worker-runtime changes, explicitly mention whether a manual rebuild/recreate is required.
10. **Collect results:**
   ```bash
   ssh -p 2022 pzagent@<host> 'collect-results /workspace/delegations/<run-id>' > delegation-result.md
   scp -P 2022 -r pzagent@<host>:/workspace/delegations/<run-id>/result ./result
   ```
11. **Review medium-depth:** Verify the result matches the task brief, acceptance criteria were addressed, important commands ran, logs are consistent, and a PR/MR exists or a clear reason is given.
12. **Correction loop for weak results:** Write correction instructions to `correction.md`, upload it, increment/record correction state, and relaunch:
    ```bash
    scp -P 2022 correction.md pzagent@<host>:/workspace/delegations/<run-id>/correction.md
    ssh -p 2022 pzagent@<host> 'jq ".state=\"correction_requested\" | .correction_rounds=(.correction_rounds+1)" /workspace/delegations/<run-id>/status.json > /tmp/status.$$.json && mv /tmp/status.$$.json /workspace/delegations/<run-id>/status.json'
    ssh -p 2022 pzagent@<host> 'run-delegated-task /workspace/delegations/<run-id> <model> /workspace/delegations/<run-id>/correction.md'
    ```
13. **Final report to user:** Include task attempted, host/model, run directory, PR/MR URL, changes, verification, correction rounds, remaining risks, and next step.

## Handoff contract

Run directory:

```text
/workspace/delegations/YYYYMMDD-HHMMSS-<task-slug>/
├── 00-task-brief.md
├── 01-environment.md
├── 02-constraints.md
├── 03-acceptance-criteria.md
├── 04-input-artifacts.md
├── 10-worker-log.md
├── 11-commands.md
├── 12-output-summary.md
├── result/
│   ├── patches/
│   ├── notes/
│   └── artifacts/
└── status.json
```

Prefer summarized markdown over large raw file copies. When a repository is required, let the worker clone it directly into `/workspace/source/<project-name>`.

## Common Pitfalls

1. **Defaulting to OpenRouter.** Never rewrite the model. Pass it to OpenCode unchanged.
2. **Wrong repository root.** Use `/workspace/source/<project-name>`, not `/workspace/<project-name>` and not `/workspace/delegations/<project-name>`.
3. **Reporting without review.** Always inspect summary, log, commands, artifacts, and PR/MR URL before finalizing.
4. **Ignoring weak output.** Send the task back for correction rather than pretending it is done.
5. **Copying huge files.** Summarize context unless exact files are necessary.
6. **Forgetting active-run warning.** Concurrent runs are allowed only by explicit new invocation, but the user should be warned.

## Verification Checklist

- [ ] SSH to `<host>:2022` works as `pzagent`
- [ ] `/workspace` is writable
- [ ] `/workspace/source` exists and is writable for repository checkouts
- [ ] `opencode`, `tmux`, `gh`, `jq`, and git are available
- [ ] OpenCode auth is present and writable for OAuth token refresh; `GITHUB_TOKEN` is present
- [ ] Run directory exists under `/workspace/delegations/<run-id>`
- [ ] `status.json` transitions through `ready`/`running` to `done` or `failed`
- [ ] `12-output-summary.md` contains a free-form result
- [ ] PR/MR URL is captured for code changes
- [ ] Orchestrator review completed
- [ ] Correction round performed if result was weak
