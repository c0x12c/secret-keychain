#!/usr/bin/env bats
# Tests for secret-config.
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

@test "secret-config --show: prints current timeout (default 300s)" {
  run secret-config --show
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout=300s"* ]]
  [[ "$output" == *"test.keychain"* ]]
}

@test "secret-config --show: reflects a previously-set timeout" {
  security set-keychain-settings -t 600 -l test.keychain
  run secret-config --show
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout=600s"* ]]
}
