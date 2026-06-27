#!/usr/bin/env bats
# UX regression tests: --help on every command, create-vs-update messaging,
# confirmation bypass, empty-state/count output, and no-color-leak when piped.
load '../helpers/setup'

setup() { setup_secret_env; }
teardown() { teardown_secret_env; }

# --- --help on every command -------------------------------------------------

@test "secret --help: exit 0 with usage and a command index" {
  run secret --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: secret"* ]]
  [[ "$output" == *"secret-list"* ]]
  [[ "$output" == *"secret-rotate"* ]]
}

@test "every command supports -h with exit 0" {
  for cmd in secret-add secret-rm secret-list secret-paste secret-init \
             secret-audit secret-load secret-rotate secret-config secret-upgrade; do
    run "$cmd" -h
    [ "$status" -eq 0 ] || { echo "$cmd -h exited $status"; false; }
    [[ "$output" == *"usage:"* ]] || { echo "$cmd -h missing usage: $output"; false; }
  done
}

# --- create vs update messaging ----------------------------------------------

@test "secret-add says 'stored' on create and 'updated' on overwrite" {
  run bash -c 'echo a | secret-add K1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"stored: K1"* ]]
  run bash -c 'echo b | secret-add K1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated: K1"* ]]
  run secret K1
  [ "$output" = "b" ]
}

@test "secret-paste says 'stored' on create and 'updated' on overwrite" {
  export SECRET_CLIP="v1"
  run secret-paste P1
  [[ "$output" == *"stored: P1"* ]]
  export SECRET_CLIP="v2"
  run secret-paste P1
  [[ "$output" == *"updated: P1"* ]]
}

# --- destructive confirmation bypass -----------------------------------------

@test "secret-rm -f removes without a prompt" {
  echo x | secret-add GONE2
  run secret-rm -f GONE2
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed: GONE2"* ]]
}

# --- secret-list empty-state and count ---------------------------------------

@test "secret-list prints an empty-state when nothing is stored" {
  run secret-list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets stored"* ]]
}

@test "secret-list prints a count footer" {
  echo v1 | secret-add A
  echo v2 | secret-add B
  run secret-list
  [[ "$output" == *"A"* ]]
  [[ "$output" == *"2 secret(s)"* ]]
}

# --- no color leaks into non-TTY output --------------------------------------

@test "status output carries no ANSI escapes when not a TTY" {
  echo x | secret-add NOCOLOR
  run secret-rm -f NOCOLOR
  [[ "$output" != *$'\033'* ]]
}
