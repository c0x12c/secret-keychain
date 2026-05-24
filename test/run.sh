#!/bin/bash
# Run the test suite. Usage: test/run.sh
set -euo pipefail

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/.."

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  shellcheck bin/* install.sh agent/claude/hooks/*.sh test/stubs/* test/run.sh
  echo "ok"
else
  echo "== shellcheck (skipped — not installed) =="
fi

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found — install with: brew install bats-core" >&2
  exit 1
fi

echo "== unit =="
bats test/unit
echo "== hooks =="
bats test/hooks
