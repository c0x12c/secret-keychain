#!/usr/bin/env bats
# Update-notifier logic: semver comparison, opt-out gating, and the guarantee
# that the check never blocks or leaks to stdout when non-interactive.
load '../helpers/setup'

setup() {
  setup_secret_env
  # shellcheck source=../../lib/update.sh
  . "$REPO/lib/update.sh"
}
teardown() { teardown_secret_env; }

@test "compare: a newer latest yields an upgrade notice" {
  run secret_update_compare v0.2.1 v0.3.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.3.0"* ]]
  [[ "$output" == *"you have v0.2.1"* ]]
  [[ "$output" == *"secret-upgrade"* ]]
}

@test "compare: equal versions yield nothing" {
  run secret_update_compare v0.3.0 v0.3.0
  [ -z "$output" ]
}

@test "compare: an older 'latest' yields nothing (no downgrade nag)" {
  run secret_update_compare v0.3.0 v0.2.1
  [ -z "$output" ]
}

@test "compare: double-digit semver sorts numerically, not lexically" {
  run secret_update_compare v0.9.0 v0.10.0
  [[ "$output" == *"v0.10.0"* ]]
  run secret_update_compare v0.10.0 v0.9.0
  [ -z "$output" ]
}

@test "compare: missing args yield nothing" {
  run secret_update_compare "" v0.3.0
  [ -z "$output" ]
  run secret_update_compare v0.3.0 ""
  [ -z "$output" ]
}

@test "compare: patch and major bumps are detected; pre-release suffix ignored" {
  run secret_update_compare v0.3.0 v0.3.1
  [[ "$output" == *"v0.3.1"* ]]
  run secret_update_compare v0.9.0 v1.0.0
  [[ "$output" == *"v1.0.0"* ]]
  run secret_update_compare v0.3.0 v0.3.0-rc1
  [ -z "$output" ]
}

@test "enabled by default; disabled under opt-out and CI" {
  run secret_update_enabled
  [ "$status" -eq 0 ]
  SECRET_NO_UPDATE_CHECK=1 run secret_update_enabled
  [ "$status" -eq 1 ]
  CI=1 run secret_update_enabled
  [ "$status" -eq 1 ]
}

@test "check is a silent no-op when stderr is not a TTY (never leaks to stdout)" {
  run secret_update_check "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "secret-list output never carries an update notice when piped" {
  echo v1 | secret-add UA
  run secret-list
  [[ "$output" != *"available"* ]]
  [[ "$output" != *"secret-upgrade"* ]]
}
