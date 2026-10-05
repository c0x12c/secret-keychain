#!/bin/bash
# PreToolUse hook (Edit | Write | MultiEdit) for secret-keychain.
#
# Closes the biggest gap in the Bash-only gate: an agent writing a secret-shaped
# string into a file (.env, source, config) via the file-edit tools is otherwise
# unmonitored. Same vendor patterns as secret-gate.sh.
#
# Contract: exit 2 + {"decision":"block","reason":...} blocks the write. exit 0 allows.
#           A gate that cannot run - no jq, unreadable input, a crash - answers "ask".
# Bypass:   BYPASS_SECRET_GATE_WRITE=1
#
# shellcheck disable=SC2016  # single quotes are intentional: literal $(secret) / JSON
set -eu

[ "${BYPASS_SECRET_GATE_WRITE:-0}" = "1" ] && exit 0

GATE_NAME=secret-gate-write GATE_WHAT=write
# Fail closed, without becoming a deny-all. Claude Code stops a tool call only on
# exit 2 or a JSON deny/ask; any other exit, and a plain exit 0, lets it through
# (https://code.claude.com/docs/en/hooks, "Other exit codes"). So a gate that cannot
# do its job must say so the one way that still stops the call - an "ask", which puts
# the decision in front of the user rather than allowing silently or blocking all calls.
ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s could not check this %s (%s), so it needs your approval."}}\n' "$GATE_NAME" "$GATE_WHAT" "$1"
  exit 0
}
# shellcheck disable=SC2329  # called by the EXIT trap below
on_exit() {
  local rc=$?
  trap - EXIT
  # 0 is an allow, 2 is a block; anything else is the gate breaking.
  [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || ask "it failed with exit $rc"
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || ask "jq is not on PATH - brew install jq"
input="$(cat)"
printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 || ask "its input is not a JSON object"
# Gather the content payloads from any of Write/Edit/MultiEdit shapes:
#   Write:     .tool_input.content
#   Edit:      .tool_input.new_string  (also old_string - skip; we only care about what lands on disk)
#   MultiEdit: .tool_input.edits[].new_string
content="$(printf '%s' "$input" | jq -r '
  [
    (.tool_input.content // empty),
    (.tool_input.new_string // empty),
    (.tool_input.edits // [] | map(.new_string // empty) | join("\n"))
  ] | join("\n")
')"
[ -z "$content" ] && exit 0

# Same pattern set as secret-gate.sh. Keep these in sync.
patterns='sk-ant-[A-Za-z0-9_-]{40,}'
patterns="$patterns|sk-proj-[A-Za-z0-9_-]{40,}"
patterns="$patterns|sk-[A-Za-z0-9_-]{40,}"
patterns="$patterns|sk_(live|test)_[A-Za-z0-9]{20,}"
patterns="$patterns|rk_live_[A-Za-z0-9]{20,}"
patterns="$patterns|ghp_[A-Za-z0-9]{30,}"
patterns="$patterns|gho_[A-Za-z0-9]{30,}"
patterns="$patterns|github_pat_[A-Za-z0-9_]{60,}"
patterns="$patterns|npm_[A-Za-z0-9]{30,}"
patterns="$patterns|hf_[A-Za-z0-9]{30,}"
patterns="$patterns|xox[baprs]-[A-Za-z0-9-]{20,}"
patterns="$patterns|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}"
patterns="$patterns|AIza[A-Za-z0-9_-]{30,}"
patterns="$patterns|ntn_[A-Za-z0-9]{40,}"
patterns="$patterns|SG\.[A-Za-z0-9_.-]{60,}"
patterns="$patterns|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_.+/=-]{10,}"
patterns="$patterns|(postgres|postgresql|mysql|mongodb|redis|amqp|amqps)://[^[:space:]/@]+:[^[:space:]/@]+@"
patterns="$patterns|https?://[A-Za-z0-9._~%+-]+:[A-Za-z0-9._~%!()*+,;=-]{6,}@"
patterns="$patterns|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----"

# Strip $(secret NAME) substitutions before the pattern scan - replace with a
# single space so the resolver form is invisible to credential shapes (incl.
# conn URIs) while inline creds elsewhere still match. Same approach as
# secret-gate.sh; see that file for the rationale.
sanitized="$(echo "$content" | sed -E 's/\$\(secret [^)]+\)/ /g')"

if echo "$sanitized" | grep -qE "$patterns"; then
  echo '{"decision":"block","reason":"This write contains a secret-shaped value. Do not commit secrets to files. Store the value once via secret-add / secret-paste, then reference it at runtime with $(secret NAME)."}'
  exit 2
fi

exit 0
