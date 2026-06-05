# Changelog

All notable changes to `secret-keychain` adhere to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/c0x12c/secret-keychain/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/c0x12c/secret-keychain/releases/tag/v0.1.0
