# secret-keychain

**Encrypted, name-addressable secrets for your terminal - backed by the macOS Keychain, in ~80 lines of auditable bash.**

Stop pasting API keys into `.env` files and `export` lines. Store a secret once, under a
name, then drop it into any command - the value is read from the encrypted Keychain at call
time and handed straight to the process. It never lands in your shell history, your
environment, or a file on disk.

```sh
# store it once (hidden prompt)
secret-add GITHUB_TOKEN

# use it anywhere - only the *name* is ever typed
curl -H "Authorization: Bearer $(secret GITHUB_TOKEN)" https://api.github.com/user
```

No account, no server, no daemon, no cost. Just the Keychain you already have, made ergonomic.

<p align="center">
  <img src="demo/secret-keychain.gif" alt="Storing a secret, listing names, using it inline in a curl call, and confirming the value never persists in the environment" width="100%">
</p>

> Recorded with [VHS](https://github.com/charmbracelet/vhs) from [`demo/demo.tape`](demo/demo.tape) - regenerate with `vhs demo/demo.tape`. The demo runs against a throwaway keychain that is created and deleted by the recording; your real keychain is never touched.

**AI-agent safe by design.** An agent can *use* your secrets but never store, leak, or even see them:

<p align="center">
  <img src="demo/secret-keychain-agent.gif" alt="An AI agent reads a secret via $(secret NAME) without the value entering its transcript, then is blocked by the PreToolUse gate when it tries to store a secret or paste a raw token inline" width="100%">
</p>

> Illustrative Claude Code session - the transcript chrome is staged, but the secret resolution and both guardrail blocks are the real shipped [`secret-gate.sh`](agent/claude/hooks/secret-gate.sh) hook. More in [Use it from an AI coding agent](#use-it-from-an-ai-coding-agent); regenerate with `vhs demo/agent-demo.tape`.

---

## 60-second start

```sh
curl -fsSL https://raw.githubusercontent.com/c0x12c/secret-keychain/master/install.sh | bash
secret-init         # creates the keychain + autolock (asks for a keychain password, once)
```

The installer clones into `~/.secret-keychain` (the latest released tag), then symlinks the `secret-*` commands into `~/.local/bin`.

Bleeding edge instead of the latest release:
```sh
curl -fsSL https://raw.githubusercontent.com/c0x12c/secret-keychain/master/install.sh | bash -s -- --track master
```

Prefer to clone yourself? `git clone` the repo and run `./install.sh` from inside it - same result, any clone location works.

Make sure your install dir (`~/.local/bin`) is on `PATH`. Done - you're ready to store secrets.
To upgrade later, run `secret-upgrade` for the newest release or `secret-upgrade --track master` to keep following `master`; use `secret --version` to see what you're on. Release notes for each tag live at <https://github.com/c0x12c/secret-keychain/releases>.

---

## The whole tool in one table

| You want to… | Run this |
|---|---|
| Store a secret (hidden prompt) | `secret-add NAME` |
| Store a secret from the clipboard (safest) | copy the value, then `secret-paste NAME` |
| Update / rotate a secret | `secret-rotate NAME` |
| Print a secret | `secret NAME` |
| Use a secret in a command | `... $(secret NAME) ...` |
| List the names you've stored | `secret-list` |
| Bulk-load secrets from a file | `secret-load path/to/.env` |
| View the audit log | `secret-audit` |
| Delete a secret | `secret-rm NAME` |
| Set up the keychain (first run) | `secret-init` |
| Change the autolock duration | `secret-config <duration>` |
| Show the current autolock duration | `secret-config --show` |
| Upgrade to the latest version | `secret-upgrade` |

That's the entire surface. Everything below is just recipes for the middle column.

---

## How do I…?

### …store a secret?

**Typed in (hidden):**
```sh
secret-add STRIPE_PROD          # prompts; your typing is not echoed
```

**From the clipboard** - preferred for high-value keys, because the value never appears as a
command-line argument:
```sh
# copy the secret to your clipboard first (Cmd-C), then:
secret-paste STRIPE_PROD        # stores it and clears your clipboard
```

**Rotate / replace** an existing one - archives the old value, then prompts for the new one:
```sh
secret-rotate STRIPE_PROD
```

**Bulk-load** several secrets from a file:
```sh
secret-load .env.production
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
secret-list                     # prints names only - never values
```

### …check whether a secret exists?

```sh
secret GH_TOKEN >/dev/null 2>&1 && echo "have it" || echo "missing"
```

### …delete a secret?

```sh
secret-rm GH_TOKEN
```

### …inspect the audit log?

```sh
secret-audit            # last 50 audit entries
secret-audit --all      # full log
secret-audit --blocks   # only BLOCKED_INLINE entries
```

### …change how long the keychain stays unlocked between prompts?

Use `secret-config` to set the autolock timeout without re-running `secret-init`:

```sh
secret-config 10m            # 10 minutes - fewer password prompts during a session
secret-config --show         # print the current timeout
secret-config 1h --force     # >15m requires --force (logged with a reason)
```

Default cap is **15 minutes**. `--force` allows up to **4 hours** and writes one
line to `~/.claude/state/secret-config.log` (timestamp, user, previous → new,
reason - provide it via `SECRET_FORCE_REASON=...` or the interactive prompt).
Above 4 hours is always rejected; `0` is rejected by design.

Longer caches reduce password prompts but widen the window in which a
prompt-injection or a compromised tool output can fetch secrets without
re-prompting. The cap is a security knob, not a UX knob.

Every `secret <NAME>` fetch is also appended to
`~/.claude/state/secret-fetch.log` (name, parent PID, parent command - **never
the value**). The append is best-effort; a failed log write never breaks the
fetch.

### …upgrade to the latest version?

```sh
secret-upgrade                  # moves to the newest released tag + re-links the symlinks
secret-upgrade --track master   # keeps following master via git pull --ff-only
```

`secret-upgrade` runs against the clone the tool was installed from - the curl
installer puts that at `~/.secret-keychain`; a manual `git clone` uses wherever you
cloned. It follows the install symlink back to the repo either way. By default it
fetches tags and checks out the highest released `vX.Y.Z`; `--track master` keeps
you on the bleeding edge, and `--ref <tag|branch|sha>` pins an explicit ref.
Use `secret --version` to confirm the current tag or branch. It refuses on a dirty
working tree or when you're on a named non-`master` branch, to avoid moving WIP.
Tarball installs (no `.git/` directory) must re-clone manually. Release notes for
each tag are on the [GitHub Releases page](https://github.com/c0x12c/secret-keychain/releases).

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
| `SECRET_AUTOLOCK_SECONDS` | `300` | Initial autolock timeout applied by `secret-init`. After setup, change it with `secret-config <duration>`. |
| `SECRET_STATE_DIR` | `~/.claude/state` | Where `secret` writes the per-fetch audit log and `secret-config` writes the `--force` log. |
| `SECRET_FORCE_REASON` | _(unset)_ | Reason recorded by `secret-config <dur> --force`. If unset and stdin is a TTY, the script prompts; otherwise the log records `unspecified`. |
| `SECRET_NO_UPDATE_CHECK` | _(unset)_ | Set to `1` to disable the "new version available" notice. Also auto-skipped under `CI` and whenever stderr isn't a TTY. |
| `SECRET_UPDATE_INTERVAL` | `86400` | Minimum seconds between background version checks (default once/day). |
| `NO_COLOR` | _(unset)_ | Honored by every command - disables ANSI color in status output. |

### Update notices

Low-frequency commands (`secret-list`, `secret-init`, `secret-add`) print a
one-line notice to stderr when a newer released tag exists, pointing you at
`secret-upgrade`. The check is throttled (once/day) and non-blocking: it refreshes
a cache in the background, so the notice appears on a later run and never delays
the command. It never auto-upgrades, never runs on the hot-path `secret` fetch,
and stays silent under `CI`, when piped, or with `SECRET_NO_UPDATE_CHECK=1`.

---

## Why it's safe

- **Encrypted at rest.** Secrets live in the macOS Keychain, not in plaintext files.
- **Out of your history when read.** `$(secret NAME)` resolves in the child process - the
  value never enters your shell history or environment. (`secret-add` still passes the value
  to `security` as `-w VALUE`, so it is briefly visible in `ps` during storage - prefer
  `secret-paste` for crown jewels.)
- **Isolated.** A dedicated keychain (`ai.keychain`) with its own password, separate from your
  login keychain, so a script that reads secrets can't silently reach everything you own.
- **Auto re-locks.** After the configured timeout of idle time, or on sleep - macOS prompts
  to unlock on the next read. Default is 5 minutes; `secret-config` adjusts it within a 15m
  cap (up to 4h with `--force`, logged with a reason).
- **Every fetch is audited.** `secret <NAME>` appends one line to
  `~/.claude/state/secret-fetch.log`: timestamp, name, parent PID, parent command. The value
  is never written. Useful for "what did the agent pull while the cache was open?"

### Known limits - read these

- **Universal Clipboard.** `secret-paste` clears the local clipboard via `pbcopy </dev/null`,
  but if Handoff / Universal Clipboard is enabled the value has already replicated to other
  Apple devices' clipboards. Disable Handoff for the run, or copy a throwaway string after.
- **`unset` is not zeroing.** `secret-add` clears `$value` from the shell's symbol table on
  exit, but does not zero the memory pages - the kernel handles that on process exit.
- **Single-user namespace.** Every command in this repo shares one keychain (default
  `ai.keychain`). Use `SECRET_KEYCHAIN=work.keychain` to split work/personal. Per-repo
  namespaces are not yet a built-in feature.

## Use it from an AI coding agent

Coding agents (Claude Code, etc.) can read secrets safely without ever seeing the value in
plaintext: they call `$(secret NAME)` inline and are blocked from storing or deleting secrets.
See the [agent demo above](#secret-keychain) for the read-safe / blocked-write flow in action.

See [`agent/AGENTS.md`](agent/AGENTS.md) for the rules. The Claude Code guardrails in
[`agent/claude/`](agent/claude/) ship as three layers:

- `permissions.deny` - hard wall against `secret-add` / `secret-paste` / `secret-rm` / `secret-load` / `secret-rotate`.
- `secret-gate.sh` - PreToolUse on `Bash`: blocks mutations and inline secret-shaped strings
  in commands (Stripe, GitHub, npm, JWT, AWS, GCP, Anthropic, OpenAI, connection URIs with
  embedded passwords, curl `-u user:secret`).
- `secret-gate-write.sh` - PreToolUse on `Edit | Write | MultiEdit`: same patterns, applied to
  file contents so an agent can't quietly land a secret in `.env` or source.

Both hooks fail loud (stderr warning) if `jq` isn't on `PATH`, so you know when the
guardrail is degraded rather than silently no-opping.

## Tests

```sh
./test/run.sh        # shellcheck + hermetic bats (stubbed Keychain) + hook tests
```

Requires [`bats-core`](https://github.com/bats-core/bats-core) (`brew install bats-core`).

## Requirements

macOS only - uses the built-in `security`, `pbpaste`/`pbcopy`, and `stty`. No other dependencies.

## License

MIT - see [LICENSE](LICENSE).
