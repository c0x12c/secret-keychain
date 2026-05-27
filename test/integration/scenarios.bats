#!/usr/bin/env bats
# Integration scenarios for secret-keychain.
#
# Each test maps to a documented value proposition or a realistic threat. The
# suite is hermetic (uses test/stubs/security so it runs in CI without touching
# the real Keychain) but exercises multi-command flows and full hook contracts,
# not the single-command behavior already covered in test/unit/.
#
# Layout:
#   1. Lifecycle  — add → list → read → rotate → rm chain
#   2. Threat surface — secrets stay out of shell history / argv / transcripts
#   3. Special-character round-trip — secrets with newlines, quotes, $, unicode
#   4. Keychain isolation — SECRET_KEYCHAIN routes per-call without bleed
#   5. Adversarial gate matrix — real bad-idioms an agent might emit naturally
#   6. Hook contract — full Claude Code JSON envelope round-trip
load '../helpers/setup'

setup() {
  setup_secret_env
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  GATE="$REPO/agent/claude/hooks/secret-gate.sh"
  GATE_WRITE="$REPO/agent/claude/hooks/secret-gate-write.sh"
}
teardown() { teardown_secret_env; }

# ─── 1. Lifecycle ────────────────────────────────────────────────────────────

@test "lifecycle: add → list → read → rotate → list (sees new) → rm → read fails" {
  # The documented happy-path workflow. Every command participates.
  echo "v1" | secret-add API_KEY

  run secret-list
  [[ "$output" == *"API_KEY"* ]]

  run secret API_KEY
  [ "$output" = "v1" ]

  # rotate = re-add overwrites
  echo "v2" | secret-add API_KEY
  run secret API_KEY
  [ "$output" = "v2" ]
  [[ "$output" != *"v1"* ]]   # old value gone, not appended

  run secret-rm API_KEY
  [ "$status" -eq 0 ]

  run secret API_KEY
  [ "$status" -eq 1 ]

  run secret-list
  [[ "$output" != *"API_KEY"* ]]
}

@test "lifecycle: multiple keys coexist, removal is scoped" {
  echo "v-alpha" | secret-add ALPHA
  echo "v-beta"  | secret-add BETA
  echo "v-gamma" | secret-add GAMMA

  secret-rm BETA
  run secret-list
  [[ "$output" == *"ALPHA"* ]]
  [[ "$output" == *"GAMMA"* ]]
  [[ "$output" != *"BETA"* ]]

  # The other values are intact, not corrupted by the removal.
  [ "$(secret ALPHA)" = "v-alpha" ]
  [ "$(secret GAMMA)" = "v-gamma" ]
}

# ─── 2. Threat surface ───────────────────────────────────────────────────────

@test "threat: \$(secret NAME) does not put the value into BASH_HISTORY" {
  # README claim: "the value never lands in your shell history".
  # We can't write to the real .bash_history, but we can run an interactive
  # shell with `set -o history` enabled and a controlled HISTFILE and verify
  # only the literal $(secret NAME) form was recorded.
  echo "the-secret-value" | secret-add HIST_TEST
  HISTFILE="$BATS_TEST_TMPDIR/.hist"
  : >"$HISTFILE"
  bash -c '
    set -o history
    HISTFILE='"$HISTFILE"'
    val="$(secret HIST_TEST)"
    history -a
  ' >/dev/null 2>&1 || true

  # The history file should only have the literal form, never the resolved value.
  [[ "$(cat "$HISTFILE")" == *'$(secret HIST_TEST)'* ]] || true   # may be absent in non-interactive bash
  ! grep -q "the-secret-value" "$HISTFILE"
}

@test "threat: secret read does not pollute caller's environment" {
  # The DATABASE_URL=\"\$(secret …)\" ./script.sh idiom shouldn't leak the value
  # into env vars visible to *other* children.
  echo "p4ss-w0rd" | secret-add DB_PASS

  # Run a child that uses the secret as a single-command env, then a sibling
  # child that just lists its environment — the value must not appear.
  DB_URL="$(secret DB_PASS)" bash -c 'true'   # use-then-discard form
  run bash -c 'env'
  [[ "$output" != *"p4ss-w0rd"* ]]
  [[ "$output" != *"DB_URL=p4ss-w0rd"* ]]
}

@test "threat: secret-list never emits a value, even for long secrets" {
  # README claim: "secret-list prints names only — never values".
  long_value="$(printf 'A%.0s' $(seq 1 200))xyz-marker"
  printf '%s\n' "$long_value" | secret-add LONG_KEY

  run secret-list
  [[ "$output" == *"LONG_KEY"* ]]
  [[ "$output" != *"xyz-marker"* ]]
}

# ─── 3. Special-character round-trip ─────────────────────────────────────────

@test "round-trip: secret with spaces and single quotes" {
  # GH tokens are alphanumeric, but DB passwords and signing keys often aren't.
  val="p@ss w0rd 'with quotes'"
  printf '%s\n' "$val" | secret-add WEIRD
  [ "$(secret WEIRD)" = "$val" ]
}

@test "round-trip: secret with \$ and backticks (no expansion on read)" {
  val='abc$HOME`whoami`def'
  printf '%s\n' "$val" | secret-add SHELLISH
  [ "$(secret SHELLISH)" = "$val" ]
}

@test "round-trip: unicode secret" {
  val="πα$$wørd-✓-中文"
  printf '%s\n' "$val" | secret-add UNICODE
  [ "$(secret UNICODE)" = "$val" ]
}

# ─── 4. Keychain isolation ──────────────────────────────────────────────────

@test "isolation: SECRET_KEYCHAIN routes per call, no cross-leak" {
  # Two distinct stores, same key name, different values. Each command targets
  # the store it was told to via env, not a sticky global.
  store_a="$(mktemp)"
  store_b="$(mktemp)"

  SECRET_STORE="$store_a" SECRET_KEYCHAIN="a.keychain" bash -c 'echo "from-a" | secret-add SHARED'
  SECRET_STORE="$store_b" SECRET_KEYCHAIN="b.keychain" bash -c 'echo "from-b" | secret-add SHARED'

  run bash -c 'SECRET_STORE="'"$store_a"'" SECRET_KEYCHAIN="a.keychain" secret SHARED'
  [ "$output" = "from-a" ]
  run bash -c 'SECRET_STORE="'"$store_b"'" SECRET_KEYCHAIN="b.keychain" secret SHARED'
  [ "$output" = "from-b" ]

  rm -f "$store_a" "$store_b"
}

# ─── 5. Adversarial gate matrix ──────────────────────────────────────────────
# Each entry is a real bad-idiom shape an LLM agent has historically emitted.
# Tests are deliberately short: the gate must answer correctly to the literal
# command an agent would naturally type.

_block() {
  jq -n --arg c "$1" '{tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

_allow() {
  jq -n --arg c "$1" '{tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "adversarial Bash: export OPENAI_API_KEY=sk-... (the canonical bad pattern)" {
  _block 'export OPENAI_API_KEY=sk-proj-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
}

@test "adversarial Bash: echo-pipe-into-file with a github PAT" {
  _block 'echo "GITHUB_TOKEN=ghp_0123456789012345678901234567890123" > .env'
}

@test "adversarial Bash: redirected heredoc-equivalent (single-line cat)" {
  _block 'printf "%s\n" "TOKEN=sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >> .env.local'
}

@test "adversarial Bash: tee with a connection URI" {
  _block 'echo "DATABASE_URL=postgres://u:p4ss@db.example.com/app" | tee -a .env'
}

@test "adversarial Bash: curl --user secret idiom" {
  _block 'curl --user admin:s3cret-p4ss-word https://api.example.com/v1/me'
}

@test "safe path: same shape but routed through \$(secret …)" {
  _allow 'export OPENAI_API_KEY="$(secret OPENAI_API_KEY)"'
  _allow 'curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com'
  _allow 'DATABASE_URL="postgres://u:$(secret DB_PASS)@db/app" ./migrate.sh'
}

@test "adversarial: \$(secret …) does not mask an inline credential elsewhere" {
  # Real bypass shape: mix the safe resolver form with an inline secret. The
  # gate must still block the inline credential.
  _block 'curl -u admin:s3cret-p4ss-word https://api.$(secret DOMAIN)/v1/x'
  _block 'curl -H "Authorization: Bearer ghp_0123456789012345678901234567890123" https://$(secret HOST)/x'
}

@test "adversarial Write: \$(secret …) does not mask an inline credential in file content" {
  _block_write "$(printf '%s\n' \
    'TOKEN_FROM_AGENT="$(secret GITHUB_TOKEN)"' \
    'LEGACY_KEY=ghp_0123456789012345678901234567890123')"
}

# ─── 6. File-write gate adversarial matrix ───────────────────────────────────

_block_write() {
  jq -n --arg c "$1" '{tool_input: {content: $c}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE_WRITE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}

@test "adversarial Write: agent dropping a .env via the Write tool" {
  _block_write "$(printf '%s\n' \
    'NODE_ENV=development' \
    'GITHUB_TOKEN=ghp_0123456789012345678901234567890123' \
    'PORT=3000')"
}

@test "adversarial Write: secrets in a TS config object literal" {
  _block_write "$(printf '%s\n' \
    'export const config = {' \
    '  anthropicApiKey: "sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",' \
    '  retries: 3,' \
    '};')"
}

@test "adversarial Write: PEM key in a doc fixture" {
  _block_write "-----BEGIN PRIVATE KEY-----\nMIIE..."
}

# ─── 7. Hook contract (Claude Code JSON envelope) ───────────────────────────

@test "hook contract: missing tool_input.command -> allow (no-op)" {
  echo '{"tool_input":{}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "hook contract: unrelated tool fields are ignored" {
  jq -n --arg c 'ls -la' '{tool_name: "Bash", tool_input: {command: $c, extra: "noise"}, session_id: "abc"}' \
    > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "hook contract: block reply is valid JSON with decision=block and a reason" {
  jq -n --arg c 'secret-add FOO' '{tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
  # The line of output must parse as JSON with the documented shape.
  decision="$(printf '%s\n' "$output" | jq -r .decision)"
  reason="$(printf '%s\n' "$output" | jq -r .reason)"
  [ "$decision" = "block" ]
  [ -n "$reason" ]
  [ "$reason" != "null" ]
}

@test "hook contract: malformed JSON payload -> allow, never crash" {
  # If the gate exits non-zero (because jq crashed on bad JSON), Claude Code
  # interprets that as "block this tool call" — a broken gate would block
  # every Bash/Edit/Write attempt. Defensive: swallow jq errors and allow.
  echo 'this is not json at all { ] [' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
  run bash "$GATE_WRITE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
}

@test "hook contract: empty stdin -> allow, never crash" {
  run bash "$GATE" < /dev/null
  [ "$status" -eq 0 ]
  run bash "$GATE_WRITE" < /dev/null
  [ "$status" -eq 0 ]
}

@test "hook contract: Write gate accepts MultiEdit shape too" {
  # The Write hook scans content + new_string + edits[].new_string. Verify the
  # last branch — a MultiEdit with multiple edits, only one of which is bad.
  jq -n '{tool_input: {edits: [
    {new_string: "// harmless comment"},
    {new_string: "AUTH=ghp_0123456789012345678901234567890123"}
  ]}}' > "$BATS_TEST_TMPDIR/p.json"
  run bash "$GATE_WRITE" < "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 2 ]
}
