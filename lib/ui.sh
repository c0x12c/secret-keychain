# shellcheck shell=bash
# Shared UI helpers for the secret-* commands. Source this file; never execute it.
#
# Contract:
#   - Status / diagnostic text goes to stderr; secret VALUES never pass through
#     here (callers print values straight to stdout).
#   - Color is emitted only when stderr is a TTY and NO_COLOR is unset, so piped
#     output, redirected logs, and the test harness all stay plain.

# Guard against double-sourcing.
[ -n "${__SECRET_UI_SOURCED:-}" ] && return 0
__SECRET_UI_SOURCED=1

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  __ui_reset=$'\033[0m'
  __ui_red=$'\033[31m'
  __ui_grn=$'\033[32m'
  __ui_yel=$'\033[33m'
  __ui_dim=$'\033[2m'
else
  __ui_reset='' __ui_red='' __ui_grn='' __ui_yel='' __ui_dim=''
fi

ui_ok()   { printf '%s%s%s\n' "$__ui_grn" "$*" "$__ui_reset" >&2; }
ui_err()  { printf '%s%s%s\n' "$__ui_red" "$*" "$__ui_reset" >&2; }
ui_warn() { printf '%s%s%s\n' "$__ui_yel" "$*" "$__ui_reset" >&2; }
ui_info() { printf '%s\n' "$*" >&2; }
ui_hint() { printf '%s  %s%s\n' "$__ui_dim" "$*" "$__ui_reset" >&2; }

# ui_confirm PROMPT -> 0 on yes, 1 otherwise. Reads a line from stdin.
# Callers MUST gate on `[ -t 0 ]` before calling, so non-interactive runs
# (pipes, automation, agents, tests) skip the prompt and proceed.
ui_confirm() {
  local prompt="$1" reply
  printf '%s [y/N] ' "$prompt" >&2
  IFS= read -r reply || return 1
  case "$reply" in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
