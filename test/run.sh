#!/bin/bash
# Run the test suite. Usage: test/run.sh
set -euo pipefail

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/.."

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  shellcheck bin/* install.sh agent/claude/hooks/*.sh test/stubs/* test/run.sh test/integration/*.sh
  echo "ok"
else
  echo "== shellcheck (skipped - not installed) =="
fi

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found - install with: brew install bats-core" >&2
  exit 1
fi

echo "== unit =="
bats test/unit
echo "== hooks =="
bats test/hooks
echo "== integration (scenarios, hermetic) =="
bats test/integration/scenarios.bats

# Live integration mutates the real security database (creates/deletes a
# throwaway keychain), so it is opt-in. Enable with RUN_LIVE=1.
if [ "${RUN_LIVE:-}" = "1" ]; then
  echo "== integration (live) =="
  bash test/integration/live.sh
else
  echo "== integration (live) - skipped (set RUN_LIVE=1 to run) =="
fi
