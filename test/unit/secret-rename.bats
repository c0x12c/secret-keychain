#!/usr/bin/env bats
# Hermetic unit tests for secret-rename (stubbed `security`).
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

@test "secret-rename: no args -> exit 64" {
  run secret-rename
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: secret-rename"* ]]
}

@test "secret-rename: only OLD given -> exit 64" {
  echo "v" | secret-add ONLY_OLD
  run secret-rename ONLY_OLD
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: secret-rename"* ]]
}

@test "secret-rename: invalid flag -> exit 64" {
  run secret-rename --wat A B
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: secret-rename"* ]]
}

@test "secret-rename: extra positional arg -> exit 64" {
  run secret-rename A B C
  [ "$status" -eq 64 ]
  [[ "$output" == *"unexpected argument: C"* ]]
}

@test "secret-rename: OLD and NEW identical -> exit 64" {
  echo "v" | secret-add SAME
  run secret-rename SAME SAME
  [ "$status" -eq 64 ]
  [[ "$output" == *"same name"* ]]
}

@test "secret-rename: missing OLD -> exit 1" {
  run secret-rename NOPE SOMETHING
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "secret-rename moves the value and removes the old name" {
  echo "s3cr3t" | secret-add OLD_NAME
  run secret-rename OLD_NAME NEW_NAME
  [ "$status" -eq 0 ]
  [[ "$output" == *"renamed: OLD_NAME -> NEW_NAME"* ]]

  run secret NEW_NAME
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t" ]

  run secret OLD_NAME
  [ "$status" -eq 1 ]
}

@test "secret-rename never prints the value" {
  echo "tops3cret-value" | secret-add QUIET
  run secret-rename QUIET RENAMED
  [ "$status" -eq 0 ]
  [[ "$output" != *"tops3cret-value"* ]]
}

@test "secret-rename: refuses to clobber an existing NEW without -f" {
  echo "keep-me" | secret-add TARGET
  echo "source"  | secret-add SOURCE
  run secret-rename SOURCE TARGET
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]

  # Both must survive a refusal - nothing moved, nothing destroyed.
  run secret TARGET
  [ "$output" = "keep-me" ]
  run secret SOURCE
  [ "$output" = "source" ]
}

@test "secret-rename -f overwrites an existing NEW" {
  echo "keep-me" | secret-add TARGET
  echo "source"  | secret-add SOURCE
  run secret-rename -f SOURCE TARGET
  [ "$status" -eq 0 ]

  run secret TARGET
  [ "$output" = "source" ]
  run secret SOURCE
  [ "$status" -eq 1 ]
}

@test "secret-rename honors a custom SECRET_KEYCHAIN" {
  export SECRET_KEYCHAIN="custom.keychain"
  echo "v" | secret-add K1
  run secret-rename K1 K2
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.keychain"* ]]
  run secret K2
  [ "$output" = "v" ]
}

@test "secret-rename: --help -> exit 0" {
  run secret-rename --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: secret-rename"* ]]
}
