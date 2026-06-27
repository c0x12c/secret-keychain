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

# secret_update_enabled -> 0 if version checks are allowed, 1 if opted out.
secret_update_enabled() {
  [ -n "${SECRET_NO_UPDATE_CHECK:-}" ] && return 1
  [ -n "${CI:-}" ] && return 1
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
  [ -t 2 ] || return 0                       # human notice only; never when piped
  [ -n "$repo" ] && [ -d "$repo/.git" ] || return 0

  state="${SECRET_STATE_DIR:-$HOME/.claude/state}/secret-update"
  interval="${SECRET_UPDATE_INTERVAL:-86400}"
  mkdir -p "$state" 2>/dev/null || return 0

  last="$(cat "$state/last-check" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  now="$(date +%s)"
  if [ "$((now - last))" -ge "$interval" ]; then
    # Refresh the cache in the background; this run uses whatever is cached now.
    # Stamp last-check FIRST so an offline/failed fetch still counts against the
    # throttle (otherwise every run would re-spawn this). The git call lives in an
    # `if` condition so its failure can't trip the subshell's inherited `set -e`.
    ( date +%s > "$state/last-check"
      newest=""
      while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        if [ -z "$newest" ] || _secret_semver_gt "$tag" "$newest"; then newest="$tag"; fi
      done < <(git -C "$repo" ls-remote --tags --refs origin 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null \
                 | sed 's#.*/##')
      [ -n "$newest" ] && printf '%s\n' "$newest" > "$state/latest"
    ) >/dev/null 2>&1 &
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
