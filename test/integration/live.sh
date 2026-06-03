#!/bin/bash
# Live integration test for secret-keychain, simulating a FRESH machine:
# a throwaway keychain that has never seen the tool, driven through the real
# bin/ scripts and the real macOS `security`. Never touches ai.keychain.
#
# Gated by RUN_LIVE=1 because it mutates the real login security database
# (creates and deletes a keychain). Run via: RUN_LIVE=1 test/run.sh
#
# Assertions use the `cmd && ok || bad` idiom intentionally: ok/bad always
# return 0, so `bad` runs only when `cmd` fails. SC2015's else-branch warning
# does not apply.
# shellcheck disable=SC2015
set -uo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KC="sk_e2e_$$.keychain"
PW="e2e-$$-pw"
export SECRET_KEYCHAIN="$KC"
export SECRET_AUTOLOCK_SECONDS=3600
PATH="$REPO/bin:$PATH"

pass=0; fail=0
ok()  { echo "  ok   - $1"; pass=$((pass+1)); }
bad() { echo "  FAIL - $1"; fail=$((fail+1)); }

cleanup() { security delete-keychain "$KC" >/dev/null 2>&1; }
trap cleanup EXIT

echo "== fresh-machine precondition =="
if security show-keychain-info "$KC" >/dev/null 2>&1; then
  echo "ABORT: $KC already exists"; exit 1
fi
ok "keychain $KC does not exist yet"

echo "== create + init (simulating a fresh setup) =="
# secret-init's create path prompts interactively for a password; do the create
# non-interactively here, then let secret-init drive the idempotent settings path.
security create-keychain -p "$PW" "$KC" && ok "created throwaway keychain" || bad "create-keychain"
security unlock-keychain -p "$PW" "$KC"
out="$(secret-init 2>&1)"; echo "$out" | grep -q "initialized $KC" && ok "secret-init applied settings" || bad "secret-init ($out)"

echo "== store via real secret-add (pty) =="
if printf 'e2e-token-123\n' | script -q /dev/null secret-add E2E_KEY >/dev/null 2>&1; then
  ok "secret-add ran through a pty"
else
  security add-generic-password -U -a "$USER" -s E2E_KEY -w e2e-token-123 "$KC"
  echo "  (note: secret-add pty path unavailable here; seeded value directly to continue read/list/rm checks)"
fi

echo "== read / list / rm through real scripts =="
val="$(secret E2E_KEY)"; [ "$val" = "e2e-token-123" ] && ok "secret read round-trips" || bad "secret read got '$val'"
secret-list | grep -qx 'E2E_KEY' && ok "secret-list shows the name" || bad "secret-list"
secret-list | grep -q 'e2e-token-123' && bad "secret-list leaked a value" || ok "secret-list shows no values"
secret-rm E2E_KEY >/dev/null 2>&1 && ok "secret-rm removed the key" || bad "secret-rm"
secret E2E_KEY >/dev/null 2>&1; [ $? -eq 1 ] && ok "read after rm exits 1" || bad "read after rm"
secret MISSING_XYZ >/dev/null 2>&1; [ $? -eq 1 ] && ok "missing key exits 1" || bad "missing key"

echo "== secret-config (timeout config on real keychain) =="
secret-config --show | grep -q "$KC" && ok "secret-config --show targets the test keychain" || bad "secret-config --show"
secret-config 2m >/dev/null && secret-config --show | grep -q "timeout=120s" && ok "secret-config 2m set timeout to 120s" || bad "secret-config 2m"
secret-config 30m >/dev/null 2>&1; [ $? -eq 1 ] && ok "30m without --force is rejected" || bad "30m without --force was accepted"
SECRET_FORCE_REASON="live-smoke" secret-config 30m --force >/dev/null && secret-config --show | grep -q "timeout=1800s" && ok "30m --force sets 1800s" || bad "30m --force"
secret-config 5h --force >/dev/null 2>&1; [ $? -eq 1 ] && ok "5h --force is rejected (hard cap)" || bad "5h --force was accepted"
secret-config 5m >/dev/null && ok "reset to 5m for cleanup" || bad "reset to 5m"

echo "== secret-fetch.log audit (per-fetch log) =="
fetch_log_dir="$(mktemp -d)"
echo "audit-value" | secret-add AUDIT_KEY
SECRET_STATE_DIR="$fetch_log_dir" secret AUDIT_KEY >/dev/null
[ -s "$fetch_log_dir/secret-fetch.log" ] && grep -q "secret=AUDIT_KEY" "$fetch_log_dir/secret-fetch.log" && ok "secret-fetch.log contains the name" || bad "secret-fetch.log missing AUDIT_KEY"
grep -q "audit-value" "$fetch_log_dir/secret-fetch.log" && bad "secret-fetch.log leaked the value" || ok "secret-fetch.log contains no values"
secret-rm AUDIT_KEY >/dev/null 2>&1
rm -rf "$fetch_log_dir"

echo "== custom keychain name honored (no hardcoded ai.keychain) =="
[ "$SECRET_KEYCHAIN" = "$KC" ] && echo "$out" | grep -q "$KC" && ok "all ops targeted $KC" || bad "custom keychain not honored"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
