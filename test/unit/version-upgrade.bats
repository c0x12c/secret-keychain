#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/git-fixture'

setup() {
  setup_secret_env
  make_git_fixture
  export PREFIX="$BATS_TEST_TMPDIR/bin"
}

teardown() {
  teardown_secret_env
}

@test "secret --version reports tag and master state" {
  git -C "$FIXTURE_CLONE" checkout --quiet v0.2.0

  run env SECRET_REPO="$FIXTURE_CLONE" "$REPO/bin/secret" --version
  [ "$status" -eq 0 ]
  [ "$output" = "v0.2.0" ]

  git -C "$FIXTURE_CLONE" checkout --quiet master

  run env SECRET_REPO="$FIXTURE_CLONE" "$REPO/bin/secret" --version
  [ "$status" -eq 0 ]
  [[ "$output" == master@* ]]
}

@test "secret-upgrade tag mode is a no-op on the highest tag" {
  git -C "$FIXTURE_CLONE" checkout --quiet v0.2.0

  run env SECRET_REPO="$FIXTURE_CLONE" PREFIX="$PREFIX" "$REPO/bin/secret-upgrade"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already on v0.2.0"* ]]
}

@test "secret-upgrade tag mode moves to the newest released tag" {
  git -C "$FIXTURE_CLONE" checkout --quiet v0.1.0
  publish_tag v0.3.0

  run env SECRET_REPO="$FIXTURE_CLONE" PREFIX="$PREFIX" "$REPO/bin/secret-upgrade"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgraded to v0.3.0"* ]]

  run env SECRET_REPO="$FIXTURE_CLONE" "$REPO/bin/secret" --version
  [ "$status" -eq 0 ]
  [ "$output" = "v0.3.0" ]
}

@test "secret-upgrade master mode keeps the clone on master" {
  git -C "$FIXTURE_CLONE" checkout --quiet master
  publish_tag v0.3.0

  run env SECRET_REPO="$FIXTURE_CLONE" PREFIX="$PREFIX" SECRET_UPGRADE_TRACK=master "$REPO/bin/secret-upgrade"
  [ "$status" -eq 0 ]
  [[ "$output" == *"upgraded:"* || "$output" == *"up to date"* ]]

  run git -C "$FIXTURE_CLONE" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

@test "secret-upgrade refuses dirty trees and named branches" {
  git -C "$FIXTURE_CLONE" checkout --quiet master
  printf 'dirty\n' >> "$FIXTURE_CLONE/tracked.txt"

  run env SECRET_REPO="$FIXTURE_CLONE" PREFIX="$PREFIX" "$REPO/bin/secret-upgrade"
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted"* ]]

  git -C "$FIXTURE_CLONE" checkout --quiet --force master
  git -C "$FIXTURE_CLONE" checkout --quiet -b ducdt/wip

  run env SECRET_REPO="$FIXTURE_CLONE" PREFIX="$PREFIX" "$REPO/bin/secret-upgrade"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to move your work"* ]]

  run git -C "$FIXTURE_CLONE" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "ducdt/wip" ]
}
