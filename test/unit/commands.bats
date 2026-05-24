#!/usr/bin/env bats
# Hermetic unit tests for the six commands (stubbed `security`/pbpaste/pbcopy/stty).
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

@test "secret: no args -> usage and exit 64" {
  run secret
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: secret"* ]]
}

@test "secret-add then secret round-trips the value" {
  echo "s3cr3t" | secret-add API_KEY
  run secret API_KEY
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t" ]
}

@test "secret-add overwrites (rotate) an existing value" {
  echo "old" | secret-add API_KEY
  echo "new" | secret-add API_KEY
  run secret API_KEY
  [ "$output" = "new" ]
}

@test "secret-add: empty value aborts with exit 1" {
  run bash -c 'echo "" | secret-add EMPTY'
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty value"* ]]
}

@test "secret: missing key -> exit 1 with add hint" {
  run secret NOPE
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"secret-add NOPE"* ]]
}

@test "secret-list prints names only, never values" {
  echo "v1" | secret-add ALPHA
  echo "v2" | secret-add BETA
  run secret-list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALPHA"* ]]
  [[ "$output" == *"BETA"* ]]
  [[ "$output" != *"v1"* ]]
  [[ "$output" != *"v2"* ]]
}

@test "secret-rm removes a key" {
  echo "x" | secret-add GONE
  run secret-rm GONE
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed: GONE"* ]]
  run secret GONE
  [ "$status" -eq 1 ]
}

@test "secret-rm: missing key -> exit 1" {
  run secret-rm NOPE
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "secret-rm: no args -> exit 64" {
  run secret-rm
  [ "$status" -eq 64 ]
}

@test "secret-paste stores from clipboard then clears it" {
  export SECRET_CLIP="from-clip"
  run secret-paste PASTED
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard cleared"* ]]
  run secret PASTED
  [ "$output" = "from-clip" ]
}

@test "secret-paste: empty clipboard -> exit 1" {
  export SECRET_CLIP=""
  run secret-paste NADA
  [ "$status" -eq 1 ]
  [[ "$output" == *"clipboard is empty"* ]]
}

@test "secret-init: idempotent when keychain exists" {
  export SECRET_KEYCHAIN_EXISTS=1
  run secret-init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "secret-init: creates keychain when missing" {
  export SECRET_KEYCHAIN_EXISTS=0
  run secret-init
  [ "$status" -eq 0 ]
  [[ "$output" == *"initialized test.keychain"* ]]
}

@test "all commands honor a custom SECRET_KEYCHAIN (no hardcoded name)" {
  export SECRET_KEYCHAIN="custom.keychain"
  echo "v" | secret-add K
  run secret K
  [ "$output" = "v" ]
}
