# Delegation handoff format

Each run lives under:

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

## Files

- `00-task-brief.md`: objective and context for the worker.
- `01-environment.md`: worker host, model, repo path, branch, and runtime assumptions.
- `02-constraints.md`: safety and scope constraints.
- `03-acceptance-criteria.md`: done criteria.
- `04-input-artifacts.md`: paths/URLs/notes for any attached artifacts.
- `10-worker-log.md`: high-level worker log plus OpenCode output.
- `11-commands.md`: exact commands run by the worker.
- `12-output-summary.md`: final free-form worker report.
- `status.json`: machine-readable run state.
- `result/notes/pr-url.txt`: PR/MR URL, when produced.

## `status.json`

```json
{
  "run_id": "20260430-170000-example",
  "host": "192.168.1.50",
  "model": "openai/gpt-5.4",
  "created_at": "2026-04-30T15:00:00Z",
  "started_at": null,
  "completed_at": null,
  "state": "created",
  "result": null,
  "correction_rounds": 0
}
```

Supported states: `created`, `ready`, `running`, `review`, `correction_requested`, `done`, `failed`.

## Context rule

Prefer summarized markdown context over copying large raw files. Copy exact source artifacts only when the delegated task truly requires them.

## Review contract

The orchestrator reads the output summary, logs, commands, and result artifacts. It performs a medium-depth review before reporting to the user. Weak results should be sent back for correction instead of being reported as final.
