#!/usr/bin/env bats
# Tests for the PreToolUse Bash gate. Feeds a hook JSON payload on stdin and
# asserts block (exit 2) vs allow (exit 0).
load '../helpers/setup'

setup() {
  setup_secret_env
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  GATE="$REPO/agent/claude/hooks/secret-gate.sh"
}
teardown() { teardown_secret_env; }

# emit a hook payload for a given Bash command into $BATS_TEST_TMPDIR/p.json
payload() {
  jq -n --arg c "$1" '{tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/p.json"
}

@test "blocks secret-add" {
  payload "secret-add FOO"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human-only"* ]]
}

@test "blocks secret-rm and secret-paste" {
  payload "secret-rm FOO"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  payload "echo hi && secret-paste BAR"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "allows secret read and secret-list" {
  payload "secret GITHUB_TOKEN"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
  payload "secret-list"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "allows inline-secret-shaped string when wrapped in \$(secret ...)" {
  payload 'curl -H "Authorization: Bearer $(secret STRIPE)" https://api.stripe.com'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "blocks a raw inline token (github)" {
  payload 'curl -H "Authorization: Bearer ghp_0123456789012345678901234567890123" x'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Inline secret detected"* ]]
}

@test "BYPASS_SECRET_GATE=1 allows everything" {
  payload "secret-add FOO"
  BYPASS_SECRET_GATE=1 run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}
