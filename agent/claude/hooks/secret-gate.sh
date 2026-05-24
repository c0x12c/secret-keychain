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
#     settings.snippet.json, which block the mutation commands at a second layer.
#
# Contract: exit 2 + {"decision":"block","reason":...} blocks and shows the reason
#           to both the model and the user. exit 0 allows.
# Bypass:   BYPASS_SECRET_GATE=1
#
# shellcheck disable=SC2016  # single quotes are intentional: literal $(secret) / JSON
set -eu

[ "${BYPASS_SECRET_GATE:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

# 1. Block secret mutations — storing and removing are the human's job.
if echo "$cmd" | grep -qE '(^|[;&|[:space:]])secret-(add|paste|rm)([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"secret-add / secret-paste / secret-rm are human-only. The agent may only read secrets via $(secret NAME) or list names with secret-list. Ask the user to store or remove a secret."}'
  exit 2
fi

# 2. Allow commands that resolve through $(secret ...) — the safe path.
echo "$cmd" | grep -q '\$(secret ' && exit 0

# 3. Block inline secret-shaped strings — force the resolver instead.
patterns='sk-[A-Za-z0-9_-]{20,}|sk_(live|test)_[A-Za-z0-9]{20,}|rk_live_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{60,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[A-Za-z0-9_-]{30,}|ntn_[A-Za-z0-9]{40,}|SG\.[A-Za-z0-9_.-]{60,}'
if echo "$cmd" | grep -qE "$patterns"; then
  echo '{"decision":"block","reason":"Inline secret detected. Use $(secret NAME) instead, e.g. curl -H \"Authorization: Bearer $(secret YOUR_KEY)\" ... . Run secret-list for available names."}'
  exit 2
fi

exit 0
