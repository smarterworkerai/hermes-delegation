# Troubleshooting

## SSH key rejected

Check host permissions and ownership:

```bash
chmod 700 ~/.pzagent
chmod 600 ~/.pzagent/authorized_keys
sudo chown 1000:1000 ~/.pzagent/authorized_keys ~/pzagent_work
```

Then inspect container logs:

```bash
docker compose logs --tail=200 hermes-worker
```

## Password login works or is prompted

Password authentication should be disabled. Confirm the active SSH config:

```bash
docker compose exec hermes-worker sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers'
```

## Missing OpenCode auth

The host file must exist:

```bash
test -f ~/.local/share/opencode/auth.json && echo ok
```

Inside the worker:

```bash
ssh -p 2022 pzagent@<host> 'test -f ~/.local/share/opencode/auth.json && echo opencode-auth-ok'
```

## Missing `GITHUB_TOKEN`

Put it in `~/.pzagent/.worker-env` and restart:

```bash
chmod 600 ~/.pzagent/.worker-env
docker compose restart hermes-worker
ssh -p 2022 pzagent@<host> 'test -n "$GITHUB_TOKEN" && echo github-token-ok'
```

## `/workspace` is not writable

The mounted `~/pzagent_work` directory should be owned by UID/GID `1000:1000`:

```bash
sudo chown -R 1000:1000 ~/pzagent_work
ssh -p 2022 pzagent@<host> 'touch /workspace/.write-test && rm /workspace/.write-test'
```

## OpenCode task stuck

List tmux sessions and inspect output:

```bash
ssh -p 2022 pzagent@<host> 'tmux ls || true'
ssh -p 2022 pzagent@<host> 'tmux capture-pane -p -t <session> | tail -80'
```

## Latest run directory

```bash
ssh -p 2022 pzagent@<host> 'ls -td /workspace/delegations/* | head -1'
ssh -p 2022 pzagent@<host> 'jq . /workspace/delegations/<run-id>/status.json'
```

## PR/MR creation failed

Check GitHub auth and repo remote:

```bash
ssh -p 2022 pzagent@<host> 'gh auth status || true'
ssh -p 2022 pzagent@<host> 'test -n "$GITHUB_TOKEN" && echo token-present'
```

The worker should use `GITHUB_TOKEN`; do not add unrelated secrets for the first implementation.

## Cleanup

Never auto-delete active or failed runs. After reviewing a completed run, delete explicitly:

```bash
rm -rf /workspace/delegations/<old-run-id>
```

`cleanup-old-runs` is dry-run only and prints candidates.
