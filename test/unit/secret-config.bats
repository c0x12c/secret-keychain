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
