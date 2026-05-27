#!/usr/bin/env bats
# Tests for the PreToolUse Edit/Write/MultiEdit gate. Feeds a hook JSON payload
# on stdin and asserts block (exit 2) vs allow (exit 0).
load '../helpers/setup'

setup() {
  setup_secret_env
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  GATE="$REPO/agent/claude/hooks/secret-gate-write.sh"
}
teardown() { teardown_secret_env; }

write_payload() {
  jq -n --arg c "$1" '{tool_input: {content: $c}}' > "$BATS_TEST_TMPDIR/p.json"
}
edit_payload() {
  jq -n --arg c "$1" '{tool_input: {new_string: $c}}' > "$BATS_TEST_TMPDIR/p.json"
}
multiedit_payload() {
  jq -n --arg c "$1" '{tool_input: {edits: [{new_string: $c}]}}' > "$BATS_TEST_TMPDIR/p.json"
}

@test "Write: blocks .env with anthropic secret" {
  # Use the Anthropic shape rather than Stripe/GitHub — GitHub Push Protection
  # validates Stripe/GitHub key shapes regardless of payload entropy and would
  # reject this commit. Anthropic isn't on the partner-scanner list.
  write_payload "ANTHROPIC_API_KEY=sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"secret-shaped"* ]]
}

@test "Edit: blocks github PAT in new_string" {
  edit_payload 'token = "ghp_0123456789012345678901234567890123"'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "MultiEdit: blocks postgres URL with password in any edit" {
  multiedit_payload 'DATABASE_URL=postgres://u:p4ss@db.example.com/app'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "Write: blocks PEM private key block" {
  write_payload "-----BEGIN RSA PRIVATE KEY-----"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "Write: allows benign config" {
  write_payload "PORT=8080
LOG_LEVEL=info
DB_HOST=localhost"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "Write: allows \$(secret …) reference in script" {
  write_payload 'curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "BYPASS_SECRET_GATE_WRITE=1 allows secret content" {
  write_payload "ANTHROPIC_API_KEY=sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  BYPASS_SECRET_GATE_WRITE=1 run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "missing jq -> stderr warning, exit 0 (degraded mode)" {
  mkdir -p "$BATS_TEST_TMPDIR/pathsbx"
  for util in bash grep cat echo; do
    ln -sf "$(command -v $util)" "$BATS_TEST_TMPDIR/pathsbx/$util"
  done
  run bash -c "PATH='$BATS_TEST_TMPDIR/pathsbx' bash '$GATE' </dev/null 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"guardrail DISABLED"* ]]
}
