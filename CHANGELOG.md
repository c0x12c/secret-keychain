# Changelog

All notable changes to `secret-keychain` adhere to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0](https://github.com/c0x12c/secret-keychain/releases/tag/v0.1.0) - 2026-06-03

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
