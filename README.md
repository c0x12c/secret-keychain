# secret-keychain

**Encrypted, name-addressable secrets for your terminal — backed by the macOS Keychain, in ~80 lines of auditable bash.**

Stop pasting API keys into `.env` files and `export` lines. Store a secret once, under a
name, then drop it into any command — the value is read from the encrypted Keychain at call
time and handed straight to the process. It never lands in your shell history, your
environment, or a file on disk.

```sh
# store it once (hidden prompt)
secret-add GITHUB_TOKEN

# use it anywhere — only the *name* is ever typed
curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com/user
```

No account, no server, no daemon, no cost. Just the Keychain you already have, made ergonomic.

---

## 60-second start

```sh
git clone https://github.com/c0x12c/secret-keychain.git
cd secret-keychain
./install.sh        # symlinks the commands into ~/.local/bin
secret-init         # creates the keychain + autolock (asks for a keychain password, once)
```

Make sure your install dir (`~/.local/bin`) is on `PATH`. Done — you're ready to store secrets.

---

## The whole tool in one table

| You want to… | Run this |
|---|---|
| Store a secret (hidden prompt) | `secret-add NAME` |
| Store a secret from the clipboard (safest) | copy the value, then `secret-paste NAME` |
| Update / rotate a secret | `secret-add NAME` again (overwrites) |
| Print a secret | `secret NAME` |
| Use a secret in a command | `... $(secret NAME) ...` |
| List the names you've stored | `secret-list` |
| Delete a secret | `secret-rm NAME` |
| Set up the keychain (first run) | `secret-init` |
| Upgrade to the latest version | `secret-upgrade` |

That's the entire surface. Everything below is just recipes for the middle column.

---

## How do I…?

### …store a secret?

**Typed in (hidden):**
```sh
secret-add STRIPE_PROD          # prompts; your typing is not echoed
```

**From the clipboard** — preferred for high-value keys, because the value never appears as a
command-line argument:
```sh
# copy the secret to your clipboard first (Cmd-C), then:
secret-paste STRIPE_PROD        # stores it and clears your clipboard
```

**Rotate / replace** an existing one — same command, it overwrites:
```sh
secret-add STRIPE_PROD
```

### …use a secret in a command?

**In a `curl` header:**
```sh
curl -H "Authorization: Bearer $(secret STRIPE_PROD)" https://api.stripe.com/v1/charges
```

**As an env var for a single command only** (not exported, not inherited afterward):
```sh
DATABASE_URL="$(secret DATABASE_URL)" ./migrate.sh
```

**Exported for the current shell session:**
```sh
export OPENAI_API_KEY="$(secret OPENAI_API_KEY)"
```

**Piped into a tool that reads from stdin:**
```sh
secret GH_TOKEN | gh auth login --with-token
```

**Inside your own script:**
```sh
token="$(secret GH_TOKEN)"
```

### …see what I've stored?

```sh
secret-list                     # prints names only — never values
```

### …check whether a secret exists?

```sh
secret GH_TOKEN >/dev/null 2>&1 && echo "have it" || echo "missing"
```

### …delete a secret?

```sh
secret-rm GH_TOKEN
```

### …upgrade to the latest version?

```sh
secret-upgrade                  # fast-forward pull + re-link the symlinks
```

`secret-upgrade` runs `git pull --ff-only` against the clone the tool was installed
from, then re-runs `install.sh` so new commands appear. It refuses on a dirty
working tree or a diverged branch — resolve those by hand. Tarball installs
(no `.git/` directory) must re-clone manually.

### …use a separate keychain (e.g. work vs personal)?

Set `SECRET_KEYCHAIN` and run `secret-init` once for it. Every command then targets it:
```sh
export SECRET_KEYCHAIN=work.keychain   # put this in your shell rc to make it stick
secret-init
secret-add DEPLOY_KEY
```

---

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SECRET_KEYCHAIN` | `ai.keychain` | Keychain name used by every command. |
| `SECRET_AUTOLOCK_SECONDS` | `300` | Idle/sleep autolock timeout, applied by `secret-init`. |

---

## Why it's safe

- **Encrypted at rest.** Secrets live in the macOS Keychain, not in plaintext files.
- **Out of your history when read.** `$(secret NAME)` resolves in the child process — the
  value never enters your shell history or environment. (`secret-add` still passes the value
  to `security` as `-w VALUE`, so it is briefly visible in `ps` during storage — prefer
  `secret-paste` for crown jewels.)
- **Isolated.** A dedicated keychain (`ai.keychain`) with its own password, separate from your
  login keychain, so a script that reads secrets can't silently reach everything you own.
- **Auto re-locks.** After `SECRET_AUTOLOCK_SECONDS` of idle time, or on sleep — macOS prompts
  to unlock on the next read.

### Known limits — read these

- **Universal Clipboard.** `secret-paste` clears the local clipboard via `pbcopy </dev/null`,
  but if Handoff / Universal Clipboard is enabled the value has already replicated to other
  Apple devices' clipboards. Disable Handoff for the run, or copy a throwaway string after.
- **`unset` is not zeroing.** `secret-add` clears `$value` from the shell's symbol table on
  exit, but does not zero the memory pages — the kernel handles that on process exit.
- **Single-user namespace.** Every command in this repo shares one keychain (default
  `ai.keychain`). Use `SECRET_KEYCHAIN=work.keychain` to split work/personal. Per-repo
  namespaces are not yet a built-in feature.

## Use it from an AI coding agent

Coding agents (Claude Code, etc.) can read secrets safely without ever seeing the value in
plaintext: they call `$(secret NAME)` inline and are blocked from storing or deleting secrets.
See [`agent/AGENTS.md`](agent/AGENTS.md) for the rules. The Claude Code guardrails in
[`agent/claude/`](agent/claude/) ship as three layers:

- `permissions.deny` — hard wall against `secret-add` / `secret-paste` / `secret-rm`.
- `secret-gate.sh` — PreToolUse on `Bash`: blocks mutations and inline secret-shaped strings
  in commands (Stripe, GitHub, npm, JWT, AWS, GCP, Anthropic, OpenAI, connection URIs with
  embedded passwords, curl `-u user:secret`).
- `secret-gate-write.sh` — PreToolUse on `Edit | Write | MultiEdit`: same patterns, applied to
  file contents so an agent can't quietly land a secret in `.env` or source.

Both hooks fail loud (stderr warning) if `jq` isn't on `PATH`, so you know when the
guardrail is degraded rather than silently no-opping.

## Tests

```sh
./test/run.sh        # shellcheck + hermetic bats (stubbed Keychain) + hook tests
```

Requires [`bats-core`](https://github.com/bats-core/bats-core) (`brew install bats-core`).

## Requirements

macOS only — uses the built-in `security`, `pbpaste`/`pbcopy`, and `stty`. No other dependencies.

## License

MIT — see [LICENSE](LICENSE).
