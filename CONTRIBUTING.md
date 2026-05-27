# Contributing to secret-keychain

Thanks for your interest. This tool is intentionally tiny (~80 lines of bash plus
a Claude Code agent kit), and the bar for additions is that they make it *safer*
or *smaller* — not bigger.

## Ground rules

- **One concern per PR.** Hook coverage, a new command, a doc fix — pick one.
- **Tests first.** Every command and every gate has hermetic bats coverage. A
  patch without a test will be asked for one.
- **No secrets in the repo.** `.env*` is gitignored. Never commit real tokens,
  even as fixtures — use the synthetic shapes already in `test/`.
- **Don't break the build.** `test/run.sh` must stay green. CI runs the same
  checks on every PR (shellcheck + bats on macOS).
- **Atomic commits.** Each commit passes tests on its own. Squash noise locally
  before pushing.

## Setup

Requirements: macOS (the only supported target), `bats-core`, `jq`,
`shellcheck` (optional but recommended).

```sh
brew install bats-core jq shellcheck
git clone git@github.com:c0x12c/secret-keychain.git
cd secret-keychain
test/run.sh
```

The hermetic suite never touches your real Keychain — `test/stubs/security`
swaps `security(1)` for a file-backed stub. The live e2e (`RUN_LIVE=1
test/run.sh`) does mutate the real `security` database (creates and tears down
a throwaway keychain); run it before shipping a change to the `bin/` commands
or `bin/secret-init`.

## What lives where

| Path | What it is |
|---|---|
| `bin/` | The six commands. Bash, `set -euo pipefail`, one concern each. |
| `agent/AGENTS.md` | Behavioral contract for AI agents. |
| `agent/claude/hooks/` | PreToolUse gates (Bash + Edit/Write/MultiEdit). |
| `agent/claude/settings.snippet.json` | Permissions + hook registration. |
| `test/unit/` | Hermetic bats over the commands (stubbed `security`). |
| `test/hooks/` | Hermetic bats over the gates (JSON payload on stdin). |
| `test/integration/live.sh` | Opt-in real-Keychain e2e. |

## Branching

- Branch from `master`: `<your-handle>/<short-description>`.
- Open the PR against `master`. Pull request descriptions should state the
  motivating threat or use case in one line.

## Security-sensitive changes

If a change relaxes a gate, widens a permission, or removes a guardrail,
explicitly call out the rationale in the PR description. Hardening changes
(new pattern, narrower allowlist, fail-loud rewording) need only a test.
