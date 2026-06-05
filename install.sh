#!/bin/bash
# Symlink the secret-* commands into a bin directory on your PATH.
# Usage: ./install.sh                  (installs to ~/.local/bin)
#        PREFIX=/usr/local/bin ./install.sh
set -euo pipefail

prefix="${PREFIX:-$HOME/.local/bin}"
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
track_mode=""
ref=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "install.sh: --ref requires a value" >&2
        exit 64
      fi
      ref="$2"
      shift 2
      ;;
    --track)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "install.sh: --track requires a value" >&2
        exit 64
      fi
      if [ "$2" != "master" ]; then
        echo "install.sh: only '--track master' is supported" >&2
        exit 64
      fi
      track_mode="master"
      shift 2
      ;;
    *)
      echo "install.sh: unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [ -n "$track_mode" ] && [ -n "$ref" ]; then
  echo "install.sh: use either --track master or --ref <ref>" >&2
  exit 64
fi

if [ -z "${SKIP_CHECKOUT:-}" ]; then
  if [ -d "$here/.git" ]; then
    git -C "$here" fetch --tags --quiet origin || true

    if [ "$track_mode" = "master" ]; then
      git -C "$here" checkout --quiet master
      git -C "$here" pull --ff-only --quiet origin master
    elif [ -n "$ref" ]; then
      git -C "$here" checkout --quiet "$ref"
    else
      target="$(git -C "$here" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)"
      if [ -n "$target" ]; then
        git -C "$here" checkout --quiet "$target"
      else
        echo "install.sh: no released tags found; leaving current checkout unchanged." >&2
      fi
    fi

    echo "secret-keychain $(git -C "$here" describe --tags --always)"
  else
    echo "install.sh: $here is not a git checkout; skipping version checkout." >&2
  fi
fi

mkdir -p "$prefix"
for cmd in secret secret-add secret-paste secret-list secret-rm secret-init secret-upgrade secret-config; do
  ln -sf "$here/bin/$cmd" "$prefix/$cmd"
done

echo "linked secret-* into $prefix"
case ":$PATH:" in
  *":$prefix:"*) ;;
  *) echo "note: $prefix is not on your PATH - add it, e.g. export PATH=\"$prefix:\$PATH\"" >&2 ;;
esac
echo "next: run 'secret-init' once to create the keychain"
