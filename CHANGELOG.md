# Changelog

All notable changes to `secret-keychain` adhere to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Consistent `-h` / `--help` on every command, with usage and examples; `secret
  --help` also prints a command index for discoverability.
- Shared UI layer (`lib/ui.sh`): status lines are colorized when stderr is a TTY
  and `NO_COLOR` is unset, and stay plain when piped, redirected, or under test.
  Secret values are never routed through it (still stdout-only).
- `secret-rm [-f]` confirms before deleting when run interactively; pipes,
  automation, and agents proceed unprompted (`-f`/`--yes` skips the prompt).
- `secret-list` now prints an empty-state message and a count footer (on stderr,
  so `secret-list | grep` stays clean).

### Changed
- `secret-add` / `secret-paste` distinguish create (`stored:`) from overwrite
  (`updated:`), surfacing that an existing value is being replaced. `secret-add`
  also confirms an overwrite interactively (skippable with `-f`; piped input is
  never blocked).

## [0.2.1] - 2026-06-26

### Changed
- One-line `curl ... | bash` install. `install.sh` is now self-bootstrapping:
  piped via curl it clones into `~/.secret-keychain` (override with
  `SECRET_KEYCHAIN_HOME`) and re-execs itself there, passing args through.
  Running it from inside a clone works exactly as before.
- The symlink step now links every command in `bin/` instead of a hardcoded
  list, so `secret-rotate`, `secret-load`, and `secret-audit` are linked on
  install/upgrade.

### Added
- Animated terminal demo in the README (`demo/secret-keychain.gif`), rendered
  with [VHS](https://github.com/charmbracelet/vhs) from the committed
  `demo/demo.tape`. The recording runs the real tools against a throwaway
  keychain it creates and deletes, so it never touches a real keychain.
- Agent-safety demo in the README's AI-agent section
  (`demo/secret-keychain-agent.gif`, driven by `demo/agent-demo.sh`): a staged
  Claude Code session where the secret resolution and both PreToolUse guardrail
  blocks (human-only mutation, inline-token rejection) are the real shipped
  `secret-gate.sh` hook.

## [0.2.0] - 2026-06-05

### Added
- `install.sh` now checks out the highest released `vX.Y.Z` tag by default
  (detached HEAD), prints the resolved version, then symlinks. New flags
  `--ref <tag|branch|sha>` and `--track master` opt into a specific ref or the
  bleeding edge; `SKIP_CHECKOUT=1` does symlink-only.
- `secret-upgrade` defaults to tag mode (moves to the newest released tag);
  `--track master` / `SECRET_UPGRADE_TRACK=master` preserves `git pull --ff-only`,
  and `--ref` pins an explicit ref. Refuses on a named non-`master` branch to
  protect WIP (detached-HEAD and `master` are allowed).
- `secret --version` prints the current tag, or `master@<sha>` / `<branch>@<sha>`
  / `unknown` outside a tagged checkout, sourced from `git describe`.

### Changed
- Install and upgrade now consume released tags instead of riding `master` HEAD.

## [0.1.0] - 2026-06-05

### Added
- Initial release of the `secret-keychain` tool kit.
- Commands: `secret`, `secret-add`, `secret-paste`, `secret-list`, `secret-rm`,
  `secret-init`, `secret-upgrade`, `secret-config`.
- Agent kit under `agent/`: behavioral contract (`AGENTS.md`), Claude Code
  PreToolUse hooks for Bash + Edit/Write/MultiEdit, and a permissions snippet.
- Hermetic `bats` test suite with a file-backed `security(1)` stub plus an
  opt-in real-Keychain integration suite (`RUN_LIVE=1 test/run.sh`).
- CI: shellcheck + bats on macOS via `.github/workflows/validate.yml`.

[Unreleased]: https://github.com/c0x12c/secret-keychain/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/c0x12c/secret-keychain/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/c0x12c/secret-keychain/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/c0x12c/secret-keychain/releases/tag/v0.1.0
