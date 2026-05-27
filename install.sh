#!/bin/bash
# Symlink the secret-* commands into a bin directory on your PATH.
# Usage: ./install.sh                  (installs to ~/.local/bin)
#        PREFIX=/usr/local/bin ./install.sh
set -euo pipefail

prefix="${PREFIX:-$HOME/.local/bin}"
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$prefix"
for cmd in secret secret-add secret-paste secret-list secret-rm secret-init secret-upgrade; do
  ln -sf "$here/bin/$cmd" "$prefix/$cmd"
done

echo "linked secret-* into $prefix"
case ":$PATH:" in
  *":$prefix:"*) ;;
  *) echo "note: $prefix is not on your PATH — add it, e.g. export PATH=\"$prefix:\$PATH\"" >&2 ;;
esac
echo "next: run 'secret-init' once to create the keychain"
