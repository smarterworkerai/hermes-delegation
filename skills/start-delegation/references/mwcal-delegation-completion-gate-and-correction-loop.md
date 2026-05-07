# mwcal delegation run: completion gates and correction-loop pattern

Session pattern captured from implementing `voice/docs/plans/2026-05-06-browser-voice-duplicate-output-fix-plan.md` on an always-on OpenCode worker.

## What happened

- Initial delegated run was blocked by sandbox permission denials despite a run-scoped whitelist.
- Root cause: whitelist allowed only recursive patterns (`/path/**`) and missed exact directory paths (`/path`).
- After adding corrective guidance and rerunning, worker produced code changes and `state=done`, but required deliverables were still incomplete (missing PR URL / curated summary / full validation evidence).
- Further correction rounds were required to enforce:
  - PR creation and URL artifact,
  - explicit test command outputs,
  - CI-failure fix-forward commit.

## Practical completion gate (orchestrator-side)

Treat delegation as complete only when **all** are true:

1. `status.json` is terminal (`done` or `failed`) **and** logs do not show sandbox/tool rejection as the effective outcome.
2. PR URL exists in `result/notes/pr-url.txt` (for code-change tasks).
3. `12-output-summary.md` is a curated report (not raw OpenCode transcript).
4. Validation evidence is concrete:
   - test commands listed,
   - pass/fail outcomes stated,
   - CI state checked from GitHub when available.
5. If CI fails after push, require a fix-forward correction round and re-check status checks.

## Correction-loop prompts that worked

- Explicitly list missing deliverables as a checklist.
- Provide exact commands for tests, push, and PR creation.
- Ban unnecessary file reads that can trigger permission prompts (`.env.*` etc.) when out of scope.
- Require summary update with commit SHA(s), PR URL, and residual risks.

## Whitelist rule nuance

Use both exact + recursive allow rules to avoid `external_directory` denials:

```json
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
```

This prevented directory-root access failures observed when only `/**` rules were present. Do not add a trailing wildcard deny; observed OpenCode behavior can let the broad deny override the explicit run-artifact allow rules.
