# shellcheck shell=bash
# Helpers sourced only by demo/demo.tape so the recorded GIF is self-contained.
# Not part of the tool. This stubs `curl` with a local responder so the demo
# needs no network call and no real credential: the request "succeeds" only if
# the Authorization header carries a non-empty bearer token, proving that
# $(secret NAME) actually resolved - while never printing the token itself.
curl() {
  local hdr=
  while [ $# -gt 0 ]; do
    [ "$1" = "-H" ] && hdr="$2"
    shift
  done
  case "$hdr" in
    *"Bearer "?*) printf '{"authenticated": true, "login": "octocat"}\n' ;;
    *) printf '{"message": "Requires authentication"}\n'; return 22 ;;
  esac
}
