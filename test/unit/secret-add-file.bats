#!/usr/bin/env bats
load '../helpers/setup'

setup() {
  setup_secret_env
  FILE="$BATS_TEST_TMPDIR/input.pem"
  VALUE='synthetic-file-content-42'
  printf '%s' "$VALUE" > "$FILE"
}
teardown() { teardown_secret_env; }

assert_quiet() {
  [[ "$output" != *"$VALUE"* ]]
}

@test "raw store round trips without printing the value" {
  run secret-add-file shared/test "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stored:"*"$FILE"*"raw"* ]]
  [[ "$output" == *"verified"* ]]
  assert_quiet
  [ "$(security find-generic-password -s shared/test -w)" = "$VALUE" ]
}

@test "raw store strips one trailing newline" {
  printf '\n' >> "$FILE"
  security() {
    if [ "$1" = add-generic-password ]; then
      while [ "$#" -gt 0 ]; do
        if [ "$1" = -w ]; then
          [ "$2" = 'synthetic-file-content-42' ] || return 1
          break
        fi
        shift
      done
      return 0
    fi
    printf '%s\n' 'synthetic-file-content-42'
  }
  export -f security
  run secret-add-file shared/test "$FILE"
  [ "$status" -eq 0 ]
  [ "$(security find-generic-password -s shared/test -w)" = "$VALUE" ]
  assert_quiet
}

@test "raw multiline file is rejected before keychain access and retained" {
  printf '%s\n%s\n' '-----BEGIN DUMMY-----' '-----END DUMMY-----' > "$FILE"
  security() { touch "$SECRET_STATE_DIR/keychain-touched"; return 1; }
  export -f security
  run secret-add-file --delete-source shared/test "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FILE has more than one line or non-printable bytes; keychain would return it as hex. Use --base64."* ]]
  [ ! -e "$SECRET_STATE_DIR/keychain-touched" ]
  [ ! -s "$SECRET_STORE" ]
  [ -f "$FILE" ]
}

@test "raw nonprintable bytes are rejected before keychain access and retained" {
  security() { touch "$SECRET_STATE_DIR/keychain-touched"; return 1; }
  export -f security
  for control in '\t' '\001' '\000' '\200'; do
    printf 'dummy%btext' "$control" > "$FILE"
    run secret-add-file --delete-source shared/test "$FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Use --base64."* ]]
    [ ! -e "$SECRET_STATE_DIR/keychain-touched" ]
    [ ! -s "$SECRET_STORE" ]
    [ -f "$FILE" ]
  done
}

@test "base64 store is one line and decodes to the source" {
  printf '%s\n%s\n' '-----BEGIN DUMMY-----' '-----END DUMMY-----' > "$FILE"
  run secret-add-file --base64 shared/test "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"base64"* ]]
  [[ "$output" == *"verified"* ]]
  assert_quiet
  encoded="$(security find-generic-password -s shared/test -w)"
  [[ "$encoded" != *$'\n'* ]]
  [[ "$output" != *"$encoded"* ]]
  [ "$(printf '%s' "$encoded" | base64 --decode)" = "$(cat "$FILE")" ]
}

@test "existing name reports updated" {
  secret-add-file shared/test "$FILE" >/dev/null 2>&1
  run secret-add-file shared/test "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated:"* ]]
  assert_quiet
}

@test "missing file directory empty file fifo and stdin are rejected" {
  mkdir "$BATS_TEST_TMPDIR/directory"
  : > "$BATS_TEST_TMPDIR/empty"
  mkfifo "$BATS_TEST_TMPDIR/fifo"
  for invalid in "$BATS_TEST_TMPDIR/missing" "$BATS_TEST_TMPDIR/directory" "$BATS_TEST_TMPDIR/empty" "$BATS_TEST_TMPDIR/fifo" -; do
    run secret-add-file --delete-source shared/test "$invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FILE"* ]]
    assert_quiet
  done
  [ -d "$BATS_TEST_TMPDIR/directory" ]
  [ -f "$BATS_TEST_TMPDIR/empty" ]
  [ -p "$BATS_TEST_TMPDIR/fifo" ]
  [ ! -s "$SECRET_STORE" ]
}

@test "files over 64 KiB are rejected and retained" {
  head -c 65537 /dev/zero > "$FILE"
  run secret-add-file --delete-source shared/test "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"64 KiB"* ]]
  [ -f "$FILE" ]
  [ ! -s "$SECRET_STORE" ]
  assert_quiet
}

@test "delete-source removes the file after verification" {
  run secret-add-file --delete-source shared/test "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified"* ]]
  [ ! -e "$FILE" ]
  [ "$(security find-generic-password -s shared/test -w)" = "$VALUE" ]
  assert_quiet
}

@test "verification mismatch retains source and fails quietly" {
  # Keep the existing store stub; replace only its readback for this test.
  security() {
    if [ "$1" = find-generic-password ]; then
      printf 'synthetic-mismatch\n'
    else
      command security "$@"
    fi
  }
  export -f security
  run secret-add-file --delete-source shared/test "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verification failed"* ]]
  [[ "$output" != *"synthetic-mismatch"* ]]
  [ -f "$FILE" ]
  assert_quiet
}

@test "usage and help exit codes" {
  run secret-add-file
  [ "$status" -eq 64 ]
  run secret-add-file --unknown
  [ "$status" -eq 64 ]
  run secret-add-file --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  assert_quiet
}
