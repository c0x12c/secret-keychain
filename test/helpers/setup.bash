# shellcheck shell=bash
# Common bats setup for secret-keychain tests.

_repo_root() {
  cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd
}

setup_secret_env() {
  REPO="$(_repo_root)"
  export REPO
  SECRET_STORE="$(mktemp)"
  export SECRET_STORE
  export SECRET_KEYCHAIN="test.keychain"
  export SECRET_CLIP=""
  SECRET_STATE_DIR="$(mktemp -d)"
  export SECRET_STATE_DIR
  PATH="$REPO/test/stubs:$REPO/bin:$PATH"
  export PATH
}

teardown_secret_env() {
  rm -f "${SECRET_STORE:-}" "${SECRET_STORE:-}.tmp" "${SECRET_STORE:-}.timeout"
  [ -n "${SECRET_STATE_DIR:-}" ] && rm -rf "$SECRET_STATE_DIR"
}
