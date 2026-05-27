#!/bin/bash
# PreToolUse hook (Bash) for secret-keychain.
#
# Two hard blocks (exit 2):
#   1. Mutations are human-only: secret-add / secret-paste / secret-rm. The agent
#      may only READ via $(secret NAME) or list names with secret-list.
#   2. Inline secret-shaped strings in a command — force the $(secret NAME) form.
#
# COVERAGE — this is friction, not a wall:
#   - Catches the common idioms only. It does NOT catch a secret written to a
#     temp file then re-read, nor non-standard token shapes (generic DB
#     passwords, custom tokens). Pair it with the permissions.deny rules in
#     settings.snippet.json (hard wall) and secret-gate-write.sh (Edit/Write).
#
# Contract: exit 2 + {"decision":"block","reason":...} blocks and shows the reason
#           to both the model and the user. exit 0 allows.
# Bypass:   BYPASS_SECRET_GATE=1
#
# shellcheck disable=SC2016  # single quotes are intentional: literal $(secret) / JSON
set -eu

[ "${BYPASS_SECRET_GATE:-0}" = "1" ] && exit 0

# Fail loud, not silent. Missing jq = degraded protection; the user should know.
if ! command -v jq >/dev/null 2>&1; then
  echo "secret-gate: jq not on PATH — guardrail DISABLED. Install jq (brew install jq) or set BYPASS_SECRET_GATE=1 to silence." >&2
  exit 0
fi

cmd="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

# 1. Block secret mutations — storing and removing are the human's job.
if echo "$cmd" | grep -qE '(^|[;&|[:space:]])secret-(add|paste|rm|upgrade)([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"secret-add / secret-paste / secret-rm / secret-upgrade are human-only. The agent may only read secrets via $(secret NAME) or list names with secret-list. Ask the user to store, remove, or upgrade."}'
  exit 2
fi

# 2. Allow commands that resolve through $(secret ...) — the safe path.
#    Done before pattern scan so a curl with a Bearer $(secret X) header passes
#    even if the surrounding command contains URL-shaped strings.
echo "$cmd" | grep -q '\$(secret ' && exit 0

# 3. Block inline secret-shaped strings — force the resolver instead.
#    Coverage: vendor API keys (Stripe, GitHub, npm, HF, Slack, Notion, SendGrid,
#    Anthropic, OpenAI, AWS, GCP), JWTs, connection URIs with embedded passwords,
#    and curl basic-auth -u/--user flags. Update this block when adding a new
#    vendor; keep each shape on its own line for readability.
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
patterns="$patterns|(^|[[:space:]])-u[[:space:]]+[^[:space:]]+:[^[:space:]]"
patterns="$patterns|(^|[[:space:]])--user[[:space:]]+[^[:space:]]+:[^[:space:]]"

if echo "$cmd" | grep -qE "$patterns"; then
  echo '{"decision":"block","reason":"Inline secret detected. Use $(secret NAME) instead, e.g. curl -H \"Authorization: Bearer $(secret YOUR_KEY)\" ... . Run secret-list for available names."}'
  exit 2
fi

exit 0
