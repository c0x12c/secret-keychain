# Using secret-keychain from an AI coding agent

This guide tells an AI coding agent (Claude Code first; the rules generalize to any
agent) how to use `secret-keychain` safely. The core idea: **the agent reads secrets,
the human manages them.**

## The one rule

> Fetch a secret only with `$(secret NAME)`, inline, at the point of use.
> Never print it, never write it to a file, never store or delete secrets.

```sh
# good - value resolves inside the child process, never in the transcript
curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com/user

# bad - value lands in the transcript and your shell history
echo "$(secret GITHUB_TOKEN)"
TOKEN=ghp_realsecretvalue...   # pasting a raw secret instead of referencing it
```

If you don't know the name, run `secret-list` (it prints names only, never values).
If a secret is missing, **ask the human to add it** - do not run `secret-add`.

## What the agent may and may not do

| Action | Allowed? |
|---|---|
| `secret NAME` inside `$(...)` for a command | ✅ yes |
| `secret-list` | ✅ yes |
| `secret-add` / `secret-paste` / `secret-rm` | ❌ no - human only |
| `secret-config` (set autolock duration) | ❌ no - human only |
| `secret-upgrade` (self-modify tooling) | ❌ no - human only |
| `echo`/`cat`/`tee` a secret value, or write it into a file | ❌ no |

**Why `secret-config` is human-only.** Bumping the autolock from 5m to 1h
widens the window in which a prompt-injection or a compromised tool output can
fetch secrets without re-prompting the human. The cap is a security boundary,
not a UX dial. If you want a longer cache for a long-running task, ask the
human to set it - the change is one line and they will see the prompt.

**Observability.** Every `secret <NAME>` you call appends one line to
`~/.claude/state/secret-fetch.log` (name, parent PID, parent command - never
the value). The human can review which secrets were fetched during a session,
even when the cache was open. Treat this as the audit trail behind your
ergonomics: longer caches don't hide your fetches.

## What's enforced vs. what's etiquette

Three layers back the rules above, installed from this directory:

- **`permissions.deny`** (in `settings.snippet.json`) - a hard wall: the agent
  cannot run `secret-add` / `secret-paste` / `secret-rm` / `secret-upgrade` /
  `secret-config` at all.
- **`hooks/secret-gate.sh`** (PreToolUse on Bash) - blocks the mutation and
  cache-duration commands with an explanatory message, and blocks commands
  containing an inline secret-shaped string, steering you to `$(secret NAME)`.
- **`hooks/secret-gate-write.sh`** (PreToolUse on Edit | Write | MultiEdit) -
  blocks file writes whose content carries a secret-shaped value. Closes the
  obvious gap where an agent would otherwise land `STRIPE_KEY=sk_live_…` in
  `.env` or source without ever touching Bash.

**These are friction, not a guarantee.** The gates catch common idioms only -
they will not catch a secret split across two writes, a custom token shape
(generic DB password, in-house auth string), or a value re-read from a file the
agent wrote earlier. Treat "don't surface secret values" as a rule you follow,
not a net that will always catch you. Output redaction is *not* possible after
the fact: once a value is printed, it is in the transcript. Both hooks fail
loud (stderr warning) when `jq` is missing, so a degraded guardrail is visible
rather than silent.

## Install (Claude Code)

From the repo root:

```sh
# project scope (shared with your team, git-committed)
mkdir -p .claude/hooks
cp agent/claude/hooks/secret-gate.sh        .claude/hooks/
cp agent/claude/hooks/secret-gate-write.sh  .claude/hooks/
# then merge agent/claude/settings.snippet.json into .claude/settings.json
```

The snippet uses `$CLAUDE_PROJECT_DIR/.claude/hooks/…`; for user scope
(`~/.claude/settings.json`) point each `command` at an absolute path instead.
Both hooks require `jq` on `PATH` - without it they print a warning to stderr and
exit 0 (degraded mode, visible to the user).

## Other agents

The `$(secret NAME)`-only discipline is agent-neutral. Any agent that supports
pre-execution command hooks or a command allow/deny list can reproduce the two
layers: deny `secret-add`/`secret-paste`/`secret-rm`, allow `secret`/`secret-list`,
and reject commands carrying inline secret-shaped strings.
