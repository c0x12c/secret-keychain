# Contributing to secret-keychain

Thanks for your interest. This tool is intentionally tiny (~80 lines of bash plus
a Claude Code agent kit), and the bar for additions is that they make it *safer*
or *smaller* - not bigger.

## Ground rules

- **One concern per PR.** Hook coverage, a new command, a doc fix - pick one.
- **Tests first.** Every command and every gate has hermetic bats coverage. A
  patch without a test will be asked for one.
- **No secrets in the repo.** `.env*` is gitignored. Never commit real tokens,
  even as fixtures - use the synthetic shapes already in `test/`.
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

The hermetic suite never touches your real Keychain - `test/stubs/security`
swaps `security(1)` for a file-backed stub. The live e2e (`RUN_LIVE=1
test/run.sh`) does mutate the real `security` database (creates and tears down
a throwaway keychain); run it before shipping a change to the `bin/` commands
or `bin/secret-init`.

## What lives where

| Path | What it is |
|---|---|
| `bin/` | The commands. Bash, `set -euo pipefail`, one concern each. |
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

## Extending `secret-config`

`secret-config` currently exposes one positional argument (the autolock
duration). When a second configurable knob actually has a concrete use case:

- **No secret values, ever.** Any new key holds a name, a duration, or a path -
  never a token, password, or API key. Secrets live in the keychain. The script
  header comment encodes this rule; preserve it.
- **Caps are security knobs.** The 15m default cap and 4h hard cap exist to
  bound the agent blast radius. Don't relax them without naming the threat
  model in the PR description.
- **Refactor to subcommands then, not now.** The positional form
  (`secret-config <duration>`) is the v1 shorthand for "set the timeout". A
  second key is the trigger to introduce a `git config`-style surface
  (`secret-config set <key> <value>` / `get` / `list`). Keep the existing
  positional form working as a shorthand for `set timeout`.
- **Update the agent guardrails.** Any new subcommand that changes a security
  property must be added to `agent/claude/hooks/secret-gate.sh` (mutation
  alternation) and `agent/claude/settings.snippet.json` deny list, with a
  matching bats test in `test/hooks/`.

## Releasing

Releases are driven by `CHANGELOG.md`. Editing the changelog on `master` is
what cuts a tag and a GitHub Release - there is no manual `git tag` step.

### Cutting a release

1. **Curate the changelog on a branch.** Replace the `## [Unreleased]`
   heading with the new version - do NOT keep an empty `## [Unreleased]`
   heading in this PR. The release workflow gates on the absence of that
   heading; while it is present the release refuses to fire.
   ```
   ## [0.2.0](https://github.com/c0x12c/secret-keychain/compare/v0.1.0...v0.2.0) - YYYY-MM-DD

   ### Added
   - ...

   ### Changed
   - ...

   ### Fixed
   - ...
   ```
2. **Update the link references at the bottom of the file**: drop the
   `[Unreleased]` link, and add a `[NEW]: .../compare/vPREV...vNEW` entry.
3. **Open the PR.** The `Changelog touched` check passes automatically
   because the PR edits `CHANGELOG.md`.
4. **Merge to `master`.** The `Release` workflow extracts the top versioned
   section, creates the `vX.Y.Z` tag, and publishes the GitHub Release with
   that section as the body.
5. **Re-add an empty `## [Unreleased]` heading in a follow-up PR.** Land it
   right after the tag publishes; the workflow checks the heading, sees it,
   and is a no-op. Adding `[Unreleased]: .../compare/vNEW...HEAD` to the
   link references at the same time keeps the file scannable.

The workflow is idempotent: re-running for an existing tag is a no-op. A
manual re-run is available via `Actions -> Release -> Run workflow`
(`workflow_dispatch`).

### SemVer for `secret-keychain`

- **patch** - doc, refactor, behavior-preserving bug fix.
- **minor** - new command, new `secret-config` key, new env var, new agent
  hook coverage, expanded allowlist.
- **major** - renamed or removed command or env var, changed exit codes,
  broken `$(secret NAME)` contract, narrowed default behavior in a way
  consumers must adapt to.

### `[skip changelog]` escape hatch

PRs that genuinely require no changelog entry (a CI-only tweak, a typo in
internal docs) can bypass the `Changelog touched` check by including
`[skip changelog]` in the PR body. Use sparingly - the default assumption
is that anything worth merging is worth a one-line entry.

### Dependabot

GitHub Actions versions are updated weekly by Dependabot. Minor and patch
bumps auto-merge; majors are held for manual review.
