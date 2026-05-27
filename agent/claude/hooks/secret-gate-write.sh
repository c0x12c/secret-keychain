#!/bin/bash
# PreToolUse hook (Edit | Write | MultiEdit) for secret-keychain.
#
# Closes the biggest gap in the Bash-only gate: an agent writing a secret-shaped
# string into a file (.env, source, config) via the file-edit tools is otherwise
# unmonitored. Same vendor patterns as secret-gate.sh.
#
# Contract: exit 2 + {"decision":"block","reason":...} blocks the write. exit 0 allows.
# Bypass:   BYPASS_SECRET_GATE_WRITE=1
#
# shellcheck disable=SC2016  # single quotes are intentional: literal $(secret) / JSON
set -eu

[ "${BYPASS_SECRET_GATE_WRITE:-0}" = "1" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "secret-gate-write: jq not on PATH — guardrail DISABLED. Install jq (brew install jq) or set BYPASS_SECRET_GATE_WRITE=1 to silence." >&2
  exit 0
fi

# Gather the content payloads from any of Write/Edit/MultiEdit shapes:
#   Write:     .tool_input.content
#   Edit:      .tool_input.new_string  (also old_string — skip; we only care about what lands on disk)
#   MultiEdit: .tool_input.edits[].new_string
# Defensive: a malformed payload would crash jq under `set -eu`, and Claude Code
# interprets any non-zero non-2 exit as "block this tool call". Swallow the parse
# error and fall through to allow — a broken gate must not become a deny-all.
payload="$(cat)"
content="$(printf '%s' "$payload" | jq -r '
  [
    (.tool_input.content // empty),
    (.tool_input.new_string // empty),
    (.tool_input.edits // [] | map(.new_string // empty) | join("\n"))
  ] | join("\n")
' 2>/dev/null || true)"
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

# Strip $(secret NAME) substitutions before the pattern scan — same rationale
# as secret-gate.sh: don't let the safe resolver form mask an inline credential
# elsewhere in the same payload.
sanitized="$(echo "$content" | sed -E 's/\$\(secret [^)]+\)/_SECRET_PLACEHOLDER_/g')"

if echo "$sanitized" | grep -qE "$patterns"; then
  echo '{"decision":"block","reason":"This write contains a secret-shaped value. Do not commit secrets to files. Store the value once via secret-add / secret-paste, then reference it at runtime with $(secret NAME)."}'
  exit 2
fi

exit 0
