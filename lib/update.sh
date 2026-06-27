# shellcheck shell=bash
# Non-blocking "new version available" notifier for the secret-* tools.
#
# Modern OSS-CLI behavior:
#   - Throttled: at most one network check per day (SECRET_UPDATE_INTERVAL secs).
#   - Non-blocking: the network check (`git ls-remote`) runs in the BACKGROUND and
#     only writes a cache file; the foreground command merely READS the cache and
#     prints a one-line notice. The notice therefore appears on the run AFTER a
#     refresh completes - the current invocation is never delayed.
#   - Quiet & safe: notice goes to stderr only, never stdout; never auto-upgrades.
#   - Opt out with SECRET_NO_UPDATE_CHECK=1; auto-skipped under CI and when stderr
#     is not a TTY (pipes, redirects, the test harness).

[ -n "${__SECRET_UPDATE_SOURCED:-}" ] && return 0
__SECRET_UPDATE_SOURCED=1

# _secret_truthy VALUE -> 0 if VALUE is set to a truthy token, 1 otherwise.
# Empty and the usual false tokens (0/false/no/off) are NOT truthy, so e.g.
# SECRET_NO_UPDATE_CHECK=0 does not opt out.
_secret_truthy() {
  case "${1:-}" in
    ''|0|false|FALSE|False|no|NO|No|off|OFF|Off) return 1 ;;
    *) return 0 ;;
  esac
}

# secret_update_enabled -> 0 if version checks are allowed, 1 if opted out.
secret_update_enabled() {
  _secret_truthy "${SECRET_NO_UPDATE_CHECK:-}" && return 1
  _secret_truthy "${CI:-}" && return 1
  return 0
}

# _secret_semver_gt A B -> 0 iff A is a strictly newer vX.Y.Z than B. Pure bash,
# no `sort -V` (a GNU extension that older macOS BSD `sort` lacks). Pre-release
# suffixes are ignored; missing components default to 0.
_secret_semver_gt() {
  local a="${1#v}" b="${2#v}" i x y
  local IFS=.
  # shellcheck disable=SC2206
  local -a A=($a) B=($b)
  for i in 0 1 2; do
    x="${A[i]:-0}"; y="${B[i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x=$((10#${x:-0})); y=$((10#${y:-0}))
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 1
}

# secret_update_compare CURRENT LATEST -> echo a notice line iff LATEST is a
# strictly newer semver tag than CURRENT. Pure (output only); the caller renders.
secret_update_compare() {
  local current="$1" latest="$2"
  [ -n "$current" ] && [ -n "$latest" ] || return 0
  if _secret_semver_gt "$latest" "$current"; then
    printf 'secret-keychain %s available (you have %s) - run: secret-upgrade\n' "$latest" "$current"
  fi
}

# secret_update_check REPO -> guards, throttled background refresh, then notice.
# Safe to call at the end of any low-frequency command; returns 0 always.
secret_update_check() {
  local repo="${1:-}" state interval last now current latest notice
  secret_update_enabled || return 0
  [ -t 2 ] || return 0                       # notice goes to stderr; emit only on a TTY
  [ -n "$repo" ] && [ -d "$repo/.git" ] || return 0

  state="${SECRET_STATE_DIR:-$HOME/.claude/state}/secret-update"
  interval="${SECRET_UPDATE_INTERVAL:-86400}"
  case "$interval" in ''|*[!0-9]*) interval=86400 ;; esac   # ignore a malformed value
  mkdir -p "$state" 2>/dev/null || return 0

  last="$(cat "$state/last-check" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  now="$(date +%s)"
  if [ "$((now - last))" -ge "$interval" ]; then
    # Stamp last-check in the FOREGROUND, before spawning the worker: the throttle
    # takes effect immediately (no race where several rapid invocations each spawn
    # a job) and still counts even if the background job never starts.
    date +%s > "$state/last-check" 2>/dev/null || true
    # GIT_TERMINAL_PROMPT=0 + stdin from /dev/null so a credential/passphrase
    # prompt can never hang the background job or reach the terminal. The grep
    # keeps only exact stable vX.Y.Z tags, excluding pre-releases (v0.3.0-rc1).
    ( newest=""
      while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        if [ -z "$newest" ] || _secret_semver_gt "$tag" "$newest"; then newest="$tag"; fi
      done < <(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --tags --refs origin 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null \
                 | sed 's#.*/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$')
      [ -n "$newest" ] && printf '%s\n' "$newest" > "$state/latest"
    ) >/dev/null 2>&1 </dev/null &
  fi

  latest="$(cat "$state/latest" 2>/dev/null || true)"
  [ -n "$latest" ] || return 0
  current="$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null || true)"
  [ -n "$current" ] || return 0

  notice="$(secret_update_compare "$current" "$latest")"
  [ -n "$notice" ] || return 0
  if [ -z "${NO_COLOR:-}" ]; then
    printf '\033[33m%s\033[0m\n' "$notice" >&2
  else
    printf '%s\n' "$notice" >&2
  fi
}
