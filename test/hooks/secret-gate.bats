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

@test "blocks secret-upgrade (agent must not self-modify tooling)" {
  payload "secret-upgrade"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human-only"* ]]
}

@test "blocks secret-rename (agent must not move a secret between names)" {
  payload "secret-rename OLD_NAME NEW_NAME"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human-only"* ]]
}

@test "blocks secret-rename when chained after another command" {
  payload "echo hi && secret-rename A B"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human-only"* ]]
}

@test "blocks secret-config (agent must not change cache duration)" {
  payload "secret-config 1h --force"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human-only"* ]]
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

@test "blocks anthropic sk-ant- token" {
  payload 'curl -H "x-api-key: sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" x'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks openai sk-proj- token" {
  payload 'export OPENAI_API_KEY=sk-proj-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks postgres connection URI with embedded password" {
  payload 'psql postgres://user:p4ssw0rd@db.example.com:5432/app'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks https URL with embedded basic-auth" {
  payload 'git clone https://user:t0ken-abc-xyz@github.com/c0x12c/secret-keychain.git'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks curl -u user:secret basic auth" {
  payload 'curl -u admin:s3cret-p4ss-word https://api.example.com/v1/x'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks JWT triple" {
  payload 'curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs.eyJzdWIiOiIxMjM0NTY3.SflKxwRJSMeKKF2QT4f"'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "blocks npm token" {
  payload 'echo //registry.npmjs.org/:_authToken=npm_abcdefghijklmnopqrstuvwxyz0123456789 > .npmrc'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "allows benign URL with port but no userinfo" {
  payload 'curl https://api.example.com:8443/v1/users'
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

# A gate that cannot run must not allow silently: Claude Code lets the call through
# on exit 0 and on any exit but 2, so the only safe answer left is an "ask".
@test "missing jq -> ask, never a silent allow" {
  mkdir -p "$BATS_TEST_TMPDIR/pathsbx"
  for util in bash grep cat echo; do
    ln -sf "$(command -v $util)" "$BATS_TEST_TMPDIR/pathsbx/$util"
  done
  run bash -c "PATH='$BATS_TEST_TMPDIR/pathsbx' bash '$GATE' </dev/null 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"ask"'* ]]
  [[ "$output" == *"jq is not on PATH"* ]]
}

@test "a crash part-way through -> ask, never a silent allow" {
  # jq that passes the input check and then fails: set -e ends the gate with exit 5,
  # which Claude Code would have treated as an allow.
  payload "ls"
  mkdir -p "$BATS_TEST_TMPDIR/pathsbx"
  for util in bash grep cat echo sed tr; do
    ln -sf "$(command -v $util)" "$BATS_TEST_TMPDIR/pathsbx/$util"
  done
  printf '#!/bin/bash\ncase "$*" in *object*) exit 0 ;; *) exit 5 ;; esac\n' > "$BATS_TEST_TMPDIR/pathsbx/jq"
  chmod +x "$BATS_TEST_TMPDIR/pathsbx/jq"
  run bash -c "PATH='$BATS_TEST_TMPDIR/pathsbx' bash '$GATE' < '$BATS_TEST_TMPDIR/p.json' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"ask"'* ]]
  [[ "$output" == *"exit 5"* ]]
}

@test "BYPASS_SECRET_GATE=1 still skips the gate when jq is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/pathsbx"
  ln -sf "$(command -v bash)" "$BATS_TEST_TMPDIR/pathsbx/bash"
  run bash -c "BYPASS_SECRET_GATE=1 PATH='$BATS_TEST_TMPDIR/pathsbx' bash '$GATE' </dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
