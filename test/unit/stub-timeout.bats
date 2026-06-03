#!/usr/bin/env bats
# Sanity test for the extended `security` stub.
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

@test "stub: set-keychain-settings -t N persists; show-keychain-info reflects it" {
  security set-keychain-settings -t 600 -l test.keychain
  run -0 bash -c 'security show-keychain-info test.keychain 2>&1'
  [[ "$output" == *"timeout=600s"* ]]
}

@test "stub: show-keychain-info defaults to 300s when nothing was set" {
  run -0 bash -c 'security show-keychain-info test.keychain 2>&1'
  [[ "$output" == *"timeout=300s"* ]]
}
