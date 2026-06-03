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

@test "secret-config: positional '10m' sets timeout to 600s" {
  run secret-config 10m
  [ "$status" -eq 0 ]
  run secret-config --show
  [[ "$output" == *"timeout=600s"* ]]
}

@test "secret-config: '30s' sets timeout to 30s" {
  run secret-config 30s
  [ "$status" -eq 0 ]
  run secret-config --show
  [[ "$output" == *"timeout=30s"* ]]
}

@test "secret-config: raw seconds '120' sets timeout to 120s" {
  run secret-config 120
  [ "$status" -eq 0 ]
  run secret-config --show
  [[ "$output" == *"timeout=120s"* ]]
}

@test "secret-config: rejects empty / unparseable duration with exit 64" {
  run secret-config 10x
  [ "$status" -eq 64 ]
  [[ "$output" == *"duration"* ]]
}

@test "secret-config: rejects 0 duration (would disable timeout)" {
  run secret-config 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be > 0"* ]]
}

@test "secret-config: 30m without --force is rejected (exit 1)" {
  run secret-config 30m
  [ "$status" -eq 1 ]
  [[ "$output" == *"exceeds 15m cap"* ]]
}

@test "secret-config: 30m --force sets 1800s and logs reason" {
  SECRET_FORCE_REASON="long task" run secret-config 30m --force
  [ "$status" -eq 0 ]
  run secret-config --show
  [[ "$output" == *"timeout=1800s"* ]]
  run cat "$SECRET_STATE_DIR/secret-config.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"forced timeout=1800s"* ]]
  [[ "$output" == *"reason=\"long task\""* ]]
}

@test "secret-config: --force without reason and no TTY logs 'unspecified'" {
  run secret-config 30m --force
  [ "$status" -eq 0 ]
  run cat "$SECRET_STATE_DIR/secret-config.log"
  [[ "$output" == *"reason=\"unspecified\""* ]]
}

@test "secret-config: 5h --force is rejected (hard cap)" {
  run secret-config 5h --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"hard cap"* ]]
}

@test "secret-config: 15m exactly (cap boundary) is allowed without --force" {
  run secret-config 15m
  [ "$status" -eq 0 ]
}

@test "secret-config: 4h exactly with --force is allowed" {
  SECRET_FORCE_REASON="boundary" run secret-config 4h --force
  [ "$status" -eq 0 ]
}
