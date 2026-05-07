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

Use this skill when the user says `start-delegation <host> <model>` or asks to hand off coding work to the always-on SSH OpenCode worker. The worker runs as `pzagent`, usually listens on SSH port `2022`, uses `/workspace` as the writable work area, stores run artifacts under `/workspace/delegations/<run-id>/`, keeps source checkouts under `/workspace/source/<project-name>`, and may also need writable OpenCode auth credentials at `~/.local/share/opencode/auth.json` for OAuth token refresh.

Some targets may use a non-default SSH port, username, identity file, or OpenCode path. Keep such host-specific connection details in the operator's private environment notes, not in this reusable skill.

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
- Validate that the model string exists on the worker before launch (e.g. `opencode models <provider>`). If a shorthand alias is not recognized (example: `openrouter/claude4.6opus`), map it to the canonical model id exposed by OpenCode (example: `openrouter/anthropic/claude-opus-4.6`) and report the mapping in your handoff note.

## Procedure

1. **Parse host/model.** If the user gives a task along with the invocation, use it as the task brief. Otherwise ask for the task brief.
2. **Run prerequisite checks:**
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
   ssh -p 2022 pzagent@<host> 'opencode models <provider> | head -n 200'
   ```
   If another run is active, show: `Another delegated task is already running on this worker.` Continue only because this skill invocation is explicit.

   **Port/path/auth fallback (important):** some valid targets use a non-default SSH port, alternate identity file, non-default username, or have OpenCode installed outside PATH. Use the host-specific connection details supplied by the user or by private environment notes, and keep those details out of versioned skill documentation. If `command -v opencode` fails but `~/.opencode/bin/opencode` exists, use that path and ensure the runtime env PATH includes it before launching. Distinguish public GitHub reachability (`curl https://github.com`, `git ls-remote` against a public repo) from authenticated GitHub readiness (`gh auth status`, `GITHUB_TOKEN`/`GH_TOKEN`); PR-producing delegations require authenticated GitHub, while public-network smoke tests do not.

   **Runtime env fallback (important):** if `check-worker-runtime` fails because `/home/pzagent/.config/hermes-worker/runtime.env` is missing, create a minimal non-secret runtime env before smoke testing:
   ```bash
   mkdir -p /home/pzagent/.config/hermes-worker
   umask 077
   cat > /home/pzagent/.config/hermes-worker/runtime.env <<'EOF'
export WORKSPACE=/workspace
export SOURCE_ROOT=/workspace/source
export PATH=/home/pzagent/.opencode/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export TZ=Europe/Budapest
EOF
   ```
   Do not invent or paste tokens into this file; if `GITHUB_TOKEN` is absent, report authenticated GitHub as missing.

   **Privilege-boundary fallback (important):** if host provisioning is requested (installing Java/Maven/Docker, starting services, editing system files) and `sudo -n true` fails or `sudo` prompts for password, do not stall. Immediately return a copy-paste root command block for the user to run on-host, then resume with non-root post-verification (versions, daemon/socket, group membership, smoke tests). This keeps progress moving in non-interactive SSH sessions.
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
6. **Set per-run OpenCode directory whitelist (mandatory):** before launch, write a temporary worker config that explicitly allows the active project and delegation paths. This prevents `external_directory` permission loops and keeps sandbox boundaries explicit. Do not add a broad wildcard deny; rely on OpenCode's default ask behavior for non-whitelisted paths.

   Prefer generating the JSON locally and copying it into place instead of using a remote heredoc redirect to `~/.config/opencode/opencode.json`; local Tirith can block remote dotfile redirects as `dotfile_overwrite`, causing the job to launch without the whitelist.
   ```bash
   tmp=$(mktemp)
   cat > "$tmp" <<'JSON'
{
  "agent": {
    "build": {
      "permission": {
        "external_directory": {
          "/workspace/source/<project-name>": "allow",
          "/workspace/source/<project-name>/**": "allow",
          "/workspace/delegations/<run-id>": "allow",
          "/workspace/delegations/<run-id>/**": "allow"
        }
      }
    }
  }
}
JSON
   scp -P 2022 "$tmp" pzagent@<host>:/tmp/opencode-<run-id>.json
   ssh -p 2022 pzagent@<host> 'mkdir -p ~/.config/opencode && mv /tmp/opencode-<run-id>.json ~/.config/opencode/opencode.json && opencode debug config'
   rm -f "$tmp"
   ```
   - Replace `<project-name>` and `<run-id>` before writing.
   - Verify resolved config includes the expected `external_directory` map before launch. If the config-write/copy step is blocked or `opencode debug config` does not show the allowlist, **do not launch**; fix the grant first.
   - Do **not** append an explicit `"*": "deny"` rule after the allowlist. In observed OpenCode behavior, the broad deny can still block allowed `/workspace/delegations/<run-id>` writes because the final wildcard rule wins over earlier allows. Rely on OpenCode's default `external_directory: * ask` for non-whitelisted paths; in non-interactive runs that is effectively denied/auto-rejected, while explicit allow rules keep project and run-artifact paths writable.
   - If OpenCode can access the project but still refuses to write run artifacts under `/workspace/delegations/<run-id>` (often shown as `external_directory` blocked for `11-commands.md`, `12-output-summary.md`, or `result/`), do not let artifact writes block the delivery: verify `git status`, commits, pushes, tests, and acceptance searches directly from the repo, then record the missing-artifact note in the parent conversation. For future correction rounds, consider using a repo-local handoff/report path that is already whitelisted.
7. **Launch worker job:** run `ssh -p 2022 pzagent@<host> 'run-delegated-task /workspace/delegations/<run-id> <model>'`.
   The worker launches a detached tmux session and returns immediately.
8. **Poll status:** run `ssh -p 2022 pzagent@<host> 'jq -r .state /workspace/delegations/<run-id>/status.json'`.
   Terminal states are `done` and `failed`.

9. **Inspect a live run when requested:**
   ```bash
   ssh -p 2022 pzagent@<host> 'tmux ls'
   ssh -p 2022 pzagent@<host> '/workspace/delegations/follow-delegation <run-id>'
   ssh -p 2022 pzagent@<host> 'tail -n 120 /workspace/delegations/<run-id>/10-worker-log.md'
   ssh -p 2022 pzagent@<host> 'tail -n 120 /workspace/delegations/<run-id>/12-output-summary.md'
   ssh -t -p 2022 pzagent@<host> 'tmux attach -t delegation-<run-id>'
   ```
   Prefer `/workspace/delegations/follow-delegation <run-id>` for live observation. It should wait for the run directory and log files instead of failing if the worker has not started writing yet. In practice, tailing `10-worker-log.md` and `12-output-summary.md` is often more informative than attaching to tmux, because the launcher may tee output into files while the interactive pane appears idle. Use `tmux attach` only when you specifically need the terminal state; detach with `Ctrl-b` then `d` because `Ctrl-c` can stop the worker process.
10. **Collect results:**
    ```bash
    ssh -p 2022 pzagent@<host> 'collect-results /workspace/delegations/<run-id>' > delegation-result.md
    scp -P 2022 -r pzagent@<host>:/workspace/delegations/<run-id>/result ./result
    ```

11. **Orchestrator validation gate (mandatory after step 9/10):** run at least one concrete check/test against the worker output before accepting the run (for example smoke test command, lint/build, or acceptance-criteria script). If anything fails or looks inconsistent, trigger a correction round instead of finalizing.

12. **Optional host-side worker refresh when runtime code changes:** if worker image/bootstrap/runtime code, helper scripts, or files expected under `/workspace/delegations` changed, the running worker may still be on the old container. Refresh it manually from the host repo checkout:
   ```bash
   bash scripts/manual-update-worker.sh
   ```
   The manual update script should stop the worker container, remember the previous image id, run `git pull --ff-only`, rebuild and restart the worker, then remove the previous worker image by id if it is no longer referenced. Do **not** assume there is a watchdog or marker-based auto-update flow. When reviewing worker-runtime changes, explicitly mention whether a manual rebuild/recreate is required.

13. **Restore default OpenCode config (cleanup):** remove the temporary per-run whitelist so the next run starts from a known baseline (or re-write a fresh per-run map at next launch).
    ```bash
    ssh -p 2022 pzagent@<host> 'rm -f ~/.config/opencode/opencode.json'
    ```

14. **Review medium-depth:** verify the result matches the task brief, acceptance criteria were addressed, important commands ran, logs are consistent, and a PR/MR exists (or there is a clear reason why not).

15. **Provisioning verification checklist (when task is host setup):**
    - verify tool versions explicitly (`java -version`, `mvn -version`, `docker --version`);
    - verify Docker daemon reachability (`docker run --rm hello-world`);
    - if daemon unreachable, check service state and socket (`systemctl is-active docker`, `ls -l /var/run/docker.sock`) and confirm user group membership (`id`, `getent group docker`);
    - if user was newly added to `docker` group, require re-login/newgrp before re-testing.

16. **Correction loop for weak/failed validation results:**
    ```bash
    scp -P 2022 correction.md pzagent@<host>:/workspace/delegations/<run-id>/correction.md
    ssh -p 2022 pzagent@<host> 'jq ".state=\"correction_requested\" | .correction_rounds=(.correction_rounds+1)" /workspace/delegations/<run-id>/status.json > /tmp/status.$$.json && mv /tmp/status.$$.json /workspace/delegations/<run-id>/status.json'
    ssh -p 2022 pzagent@<host> 'run-delegated-task /workspace/delegations/<run-id> <model> /workspace/delegations/<run-id>/correction.md'
    ```

16. **Final report to user:** include task attempted, host/model, run directory, PR/MR URL, checks/tests executed, correction rounds, remaining risks, and next step.

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
7. **Letting logging execute prompt substitutions.** If maintaining a `run-delegated-task`-style launcher, do not write documented commands with an unquoted heredoc that contains `$(cat "$PROMPT_FILE")`; the outer shell may evaluate it too early and emit noisy errors such as `cat: '$PROMPT_FILE': No such file or directory`. Use single-quoted heredocs or `printf %q`/literal `echo` lines so `11-commands.md` records the command without executing it.
8. **Skipping direct provider smoke after auth changes.** After OpenCode provider re-auth or credential mount changes, run a direct `opencode run --model <model> 'Reply with exactly: OPENCODE_SMOKE_OK'` before launching an end-to-end delegation smoke; if direct smoke fails, the delegation will fail at the same provider layer.
9. **Forgetting that image/bootstrap changes require container refresh.** If you add or modify worker helper scripts, bootstrap behavior, or files expected under `/workspace/delegations`, verify the currently running container actually has the change. A running worker may still be on the old image and will not gain new helpers such as `/workspace/delegations/follow-delegation` until the worker is rebuilt/recreated (for example `docker compose up -d --build`) and bootstrap runs again.
10. **Accepting a superficially `done` run after tool/sandbox rejection.** OpenCode may exit `0` and the launcher may mark the run `done` even when the actual content says permission was rejected or no implementation happened. Review `12-output-summary.md` and `10-worker-log.md` for phrases like `permission requested`, `auto-rejecting`, `user rejected permission`, or only preflight output. If this happens, send a correction that narrows work to allowed directories (for this worker, `/workspace/source/<project-name>` and `/workspace/delegations/<run-id>`), explicitly tells it not to request `/` or other external directories, and relaxes optional checks for unavailable tools (e.g. Docker) while keeping required validation.
11. **Forgetting exact-directory allow rules in the whitelist.** Some tool calls first access the directory path itself (for example `/workspace/delegations/<run-id>` or `/workspace/source/<project-name>`) before files under `/**`. If only `/**` is allowed, OpenCode can still fail with `external_directory` denials for the directory root. Include both exact paths and recursive paths in `external_directory`.
12. **Treating `done` as complete when deliverables are missing.** A run can end with `state=done` and `exit_code=0` while still missing required outputs (no PR URL, no clean summary, no validation evidence, CI failures). Apply an orchestrator completion gate: verify PR exists, required tests/CI status are green (or explicitly blocked with reason), and `12-output-summary.md` is a curated report (not raw transcript). If any gate fails, issue a correction round.
13. **Provider overload can produce a false-success delegation.** OpenCode may return `exit_code=0` and the launcher may mark `state=done` even when `10-worker-log.md` / `12-output-summary.md` contain only a provider error such as `service_unavailable_error`, `server_is_overloaded`, rate limit, or token/auth refresh failure. Treat this as weak output: run a direct provider smoke with a fallback model (for example `opencode run --model <fallback> 'Reply with exactly: OPENCODE_SMOKE_OK'`), then issue a correction/retry using the working model instead of reporting the delegation as complete.
14. **SSH identity may need to be explicit.** If the always-on worker returns `Permission denied (publickey)` while the host is known reachable, inspect `ssh -G` and local keys; retry prerequisite checks with the host-specific identity file, port, and username supplied by the user or private environment notes rather than assuming the worker is down.
15. **OpenCode can exist outside PATH on SSH workers.** If `command -v opencode` fails, check `~/.opencode/bin/opencode`. A direct provider smoke can still pass with `/home/pzagent/.opencode/bin/opencode run --model <model> 'Reply with exactly: OPENCODE_SMOKE_OK'`; add that directory to the worker runtime PATH before `run-delegated-task`.
16. **Authenticated GitHub is separate from network access.** `curl https://github.com` and public `git ls-remote` prove outbound/network access only. `gh auth status`, `gh api user`, and `GITHUB_TOKEN`/`GH_TOKEN` prove authenticated readiness. Treat missing auth as a blocker for PR/private-repo delegation but not for a public smoke task.
17. **Missing runtime.env can break worker preflight even when tools are installed.** If `/home/pzagent/.config/hermes-worker/runtime.env` is absent, create a minimal non-secret file with `WORKSPACE`, `SOURCE_ROOT`, PATH including `~/.opencode/bin`, and `TZ`, then rerun `check-worker-runtime`. Do not store invented placeholder tokens there.
18. **Forgetting per-run whitelist setup.** Always write a run-specific `~/.config/opencode/opencode.json` `external_directory` map before launch (exact + recursive project/run paths allow, no wildcard deny). This prevents avoidable permission loops and removes the need to bypass sandbox flow.

Reference: `references/mwcal-delegation-completion-gate-and-correction-loop.md` (example of multi-round completion-gate enforcement: whitelist root-path pitfall, missing-deliverable corrections, CI fix-forward loop).

## Verification Checklist

- [ ] SSH to `<host>:2022` works as `pzagent`
- [ ] `/workspace` is writable
- [ ] `/workspace/source` exists and is writable for repository checkouts
- [ ] `opencode`, `tmux`, `gh`, `jq`, and git are available
- [ ] OpenCode auth is present and writable for OAuth token refresh; `GITHUB_TOKEN` is present
- [ ] Run directory exists under `/workspace/delegations/<run-id>`
- [ ] Per-run OpenCode whitelist is set in `~/.config/opencode/opencode.json` (`external_directory` allows exact + recursive project and run directories, with no wildcard deny)
- [ ] `status.json` transitions through `ready`/`running` to `done` or `failed`
- [ ] `12-output-summary.md` contains a free-form result
- [ ] PR/MR URL is captured for code changes
- [ ] Orchestrator review completed
- [ ] Correction round performed if result was weak
