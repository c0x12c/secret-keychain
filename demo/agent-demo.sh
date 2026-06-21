#!/usr/bin/env bash
# Drives the "working with an AI coding agent" demo recorded by
# demo/agent-demo.tape. Self-contained: it creates a throwaway keychain, seeds a
# dummy token, runs the REAL secret-gate.sh PreToolUse hook for the guardrail
# beats, then deletes the keychain. The Claude Code transcript chrome (the >
# prompts and ● tool-call lines) is illustrative; the secret resolution and the
# gate decisions underneath are the actual shipped tooling.
#
# shellcheck disable=SC2016  # single quotes are intentional: the transcript must
# show the literal $(secret NAME), not its expansion.
set -u

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -P "$here/.." && pwd)"
export PATH="$repo/bin:$PATH"
export SECRET_KEYCHAIN="$HOME/sk-agent-demo.keychain"
hook="$repo/agent/claude/hooks/secret-gate.sh"

# ── sandbox keychain (created + destroyed by this script) ──────────────
security delete-keychain "$SECRET_KEYCHAIN" 2>/dev/null || true
security create-keychain -p demo "$SECRET_KEYCHAIN"
security unlock-keychain -p demo "$SECRET_KEYCHAIN"
security set-keychain-settings "$SECRET_KEYCHAIN"
# Seed a dummy token directly (-A so the read below never raises a GUI prompt).
security add-generic-password -A -U -a "$USER" -s GITHUB_TOKEN \
  -w "ghp_illustrative_demo_value_not_a_real_token" "$SECRET_KEYCHAIN"
cleanup() { security delete-keychain "$SECRET_KEYCHAIN" 2>/dev/null || true; }
trap cleanup EXIT

# Stand-in for the GitHub API: succeeds only if a bearer token arrived, and
# never echoes it - so $(secret GITHUB_TOKEN) genuinely has to resolve.
api() {
  local hdr="$1"
  case "$hdr" in
    *"Bearer "?*) printf '{"login": "octocat", "name": "The Octocat"}' ;;
    *) printf '{"message": "Requires authentication"}' ;;
  esac
}

# ── palette + Claude-Code-style transcript helpers ─────────────────────
esc=$'\033'
dim="${esc}[2m"; reset="${esc}[0m"; bold="${esc}[1m"
orange="${esc}[38;5;214m"; green="${esc}[32m"; red="${esc}[31m"; cyan="${esc}[36m"

user()      { printf '\n%s>%s %s%s%s\n'   "$bold" "$reset" "$cyan" "$1" "$reset"; sleep "$2"; }
tool()      { printf '\n%s●%s %sBash%s(%s)\n' "$orange" "$reset" "$bold" "$reset" "$1"; sleep "$2"; }
note()      { printf '%s  %s%s\n' "$dim" "$1" "$reset"; }
ok()        { printf '  %s└─%s %s%s%s\n' "$dim" "$reset" "$green" "$1" "$reset"; sleep "$2"; }
blocked()   { printf '  %s└─%s %s✗ blocked by secret-gate%s\n' "$dim" "$reset" "$red" "$reset"
              printf '     %s%s%s\n' "$dim" "$1" "$reset"; sleep "$2"; }

# Run the REAL hook against a command the way Claude Code would, and report the
# decision. Echoes nothing sensitive - just the gate's verdict + first sentence.
gate_reason() {
  local cmd="$1" out full first rest
  out="$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$hook" 2>/dev/null)"
  full="$(jq -r '.reason // empty' <<<"$out" | sed -E 's/, e\.g\..*//')"
  first="${full%%. *}."
  # a bare "Inline secret detected." loses the lesson; keep the next sentence too
  if [ "${#first}" -lt 25 ]; then
    rest="${full#"$first" }"
    first="$first ${rest%%. *}."
  fi
  printf '%s' "$first"
}

clear

# ── Beat 1: the agent reads a secret the safe way ──────────────────────
user "check that my GitHub token works - who am I?" 0.9
tool 'curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com/user' 0.9
ok "$(api "Authorization: Bearer $(secret GITHUB_TOKEN)")" 0.7
note "authenticated as octocat. only the literal \$(secret GITHUB_TOKEN) ever"
note "entered my context - the token resolved inside the child process."
sleep 1.4

# ── Beat 2: the agent tries to STORE a secret (human-only) ─────────────
user "nice. save this new one for me: NEW_KEY = sk-live-9f3a2b1c8d" 0.9
tool 'secret-add NEW_KEY' 0.7
blocked "$(gate_reason 'secret-add NEW_KEY')" 1.5

# ── Beat 3: the agent tries to hardcode a raw token inline ─────────────
user "ok then just paste the token straight into the curl" 0.9
tool 'curl -H "Authorization: Bearer ghp_EXAMPLEonly0000000000000000000000000" ...' 0.7
blocked "$(gate_reason 'curl -H "Authorization: Bearer ghp_EXAMPLEonly0000000000000000000000000" https://api.github.com/user')" 1.6

printf '\n%s  the agent can use secrets, but never store, leak, or even see them.%s\n' "$bold" "$reset"
sleep 2.2
