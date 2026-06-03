#!/usr/bin/env bats
# `secret` writes one audit line per fetch; never the secret value.
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

@test "secret: fetch appends a line to the audit log" {
  echo "s3cr3t-value" | secret-add API_KEY
  run secret API_KEY
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t-value" ]
  run cat "$SECRET_STATE_DIR/secret-fetch.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret=API_KEY"* ]]
}

@test "secret: audit log NEVER contains the secret value" {
  echo "s3cr3t-value" | secret-add API_KEY
  run secret API_KEY
  run cat "$SECRET_STATE_DIR/secret-fetch.log"
  [[ "$output" != *"s3cr3t-value"* ]]
}

@test "secret: audit log line includes timestamp, name, ppid, pcomm" {
  echo "v" | secret-add NAME
  run secret NAME
  run cat "$SECRET_STATE_DIR/secret-fetch.log"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ secret=NAME\ ppid=[0-9]+\ pcomm=.+$ ]]
}

@test "secret: a failed log write does not break the fetch" {
  echo "v" | secret-add NAME
  # Point state dir at a read-only location so the append fails.
  ro="$(mktemp -d)"; chmod 500 "$ro"
  SECRET_STATE_DIR="$ro" run secret NAME
  [ "$status" -eq 0 ]
  [ "$output" = "v" ]
  chmod 700 "$ro"; rm -rf "$ro"
}

@test "secret: fetch of a missing key still logs an attempt and exits 1" {
  run secret MISSING
  [ "$status" -eq 1 ]
  run cat "$SECRET_STATE_DIR/secret-fetch.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret=MISSING"* ]]
}
