# Using secret-keychain from an AI coding agent

This guide tells an AI coding agent (Claude Code first; the rules generalize to any
agent) how to use `secret-keychain` safely. The core idea: **the agent reads secrets,
the human manages them.**

## The one rule

> Fetch a secret only with `$(secret NAME)`, inline, at the point of use.
> Never print it, never write it to a file, never store or delete secrets.

```sh
# good — value resolves inside the child process, never in the transcript
curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com/user

# bad — value lands in the transcript and your shell history
echo "$(secret GITHUB_TOKEN)"
TOKEN=ghp_realsecretvalue...   # pasting a raw secret instead of referencing it
```

If you don't know the name, run `secret-list` (it prints names only, never values).
If a secret is missing, **ask the human to add it** — do not run `secret-add`.

## What the agent may and may not do

| Action | Allowed? |
|---|---|
| `secret NAME` inside `$(...)` for a command | ✅ yes |
| `secret-list` | ✅ yes |
| `secret-add` / `secret-paste` / `secret-rm` | ❌ no — human only |
| `echo`/`cat`/`tee` a secret value, or write it into a file | ❌ no |

## What's enforced vs. what's etiquette

Two layers back the rules above, installed from this directory:

- **`permissions.deny`** (in `settings.snippet.json`) — a hard wall: the agent
  cannot run `secret-add` / `secret-paste` / `secret-rm` at all.
- **`hooks/secret-gate.sh`** (PreToolUse on Bash) — blocks the mutation commands
  with an explanatory message, and blocks commands containing an inline
  secret-shaped string, steering you to `$(secret NAME)`.

**These are friction, not a guarantee.** The gate catches common idioms only — it
will not catch a secret written to a temp file and re-read, or a non-standard token
shape (e.g. a plain DB password). Treat "don't surface secret values" as a rule you
follow, not a net that will always catch you. Output redaction is *not* possible
after the fact: once a value is printed, it is in the transcript.

## Install (Claude Code)

From the repo root:

```sh
# project scope (shared with your team, git-committed)
mkdir -p .claude/hooks
cp agent/claude/hooks/secret-gate.sh .claude/hooks/
# then merge agent/claude/settings.snippet.json into .claude/settings.json
```

The snippet uses `$CLAUDE_PROJECT_DIR/.claude/hooks/secret-gate.sh`; for user scope
(`~/.claude/settings.json`) point the `command` at an absolute path instead.
Requires `jq` on PATH (the gate no-ops without it).

## Other agents

The `$(secret NAME)`-only discipline is agent-neutral. Any agent that supports
pre-execution command hooks or a command allow/deny list can reproduce the two
layers: deny `secret-add`/`secret-paste`/`secret-rm`, allow `secret`/`secret-list`,
and reject commands carrying inline secret-shaped strings.
