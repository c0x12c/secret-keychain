#!/bin/bash
# PreToolUse hook (Bash) for secret-keychain.
#
# Two hard blocks (exit 2):
#   1. Mutations are human-only: secret-add / secret-paste / secret-rm /
#      secret-load / secret-rotate. The agent may only READ via $(secret NAME)
#      or list names with secret-list.
#   2. Inline secret-shaped strings in a command - force the $(secret NAME) form.
#
# COVERAGE - this is friction, not a wall:
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
  echo "secret-gate: jq not on PATH - guardrail DISABLED. Install jq (brew install jq) or set BYPASS_SECRET_GATE=1 to silence." >&2
  exit 0
fi

# Defensive: a malformed JSON payload would crash jq under `set -eu`, and Claude
# Code interprets any non-zero non-2 exit as "block this tool call". Swallow the
# parse error and fall through to allow - a broken gate must not become a deny-all.
cmd="$(cat | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# 1. Block secret mutations and the cache-duration control - storing, removing,
#    upgrading, and changing the autolock window are the human's job. Letting an
#    agent extend the cache (secret-config) widens its own future blast radius.
if echo "$cmd" | grep -qE '(^|[;&|[:space:]])secret-(add|paste|rm|load|rotate|upgrade|config)([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"secret-add / secret-paste / secret-rm / secret-load / secret-rotate / secret-upgrade / secret-config are human-only. The agent may only read secrets via $(secret NAME) or list names with secret-list. secret-config (cache duration) is human-only because longer caches widen the agent blast radius. Ask the user to make the change."}'
  exit 2
fi

# 2. Strip $(secret NAME) substitutions before the pattern scan. Replace each
#    with a single space - a non-credential character that also breaks any
#    [^space/@]+ capture (so `postgres://u:$(secret PASS)@host` doesn't read
#    as a URI-with-password shape after sanitization). The surrounding command
#    is still scanned, so a real inline credential elsewhere (e.g.
#    `curl -u admin:realpass https://$(secret HOST)/x`) still blocks.
sanitized="$(echo "$cmd" | sed -E 's/\$\(secret [^)]+\)/ /g')"

# 3. Block inline secret-shaped strings - force the resolver instead.
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

if echo "$sanitized" | grep -qE "$patterns"; then
  echo '{"decision":"block","reason":"Inline secret detected. Use $(secret NAME) instead, e.g. curl -H \"Authorization: Bearer $(secret YOUR_KEY)\" ... . Run secret-list for available names."}'
  exit 2
fi

exit 0
