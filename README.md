# secret-keychain

Lazy, name-addressable secrets backed by an isolated macOS Keychain.

Fetch credentials by name, inline, so the value resolves only in the child process —
it never lands in your shell history, environment, or a file on disk:

```sh
curl -H "Authorization: Bearer $(secret STRIPE_PROD)" https://api.stripe.com/v1/charges
```

The literal `$(secret STRIPE_PROD)` is what enters your history; the secret itself is
read from the Keychain at call time and passed straight to the subprocess.

## Why

- **No plaintext at rest.** Secrets live in the macOS Keychain, not in `.env` files or exported vars.
- **Isolated keychain.** Stored in a dedicated keychain (default `ai.keychain`), separate from your
  login keychain, with its own password and idle autolock — so a tool reading secrets can't silently
  reach everything in your login keychain.
- **Name-addressable.** Reference a secret by a stable name; rotate the value without touching callers.

## Requirements

macOS only. Uses the built-in `security`, `pbpaste`/`pbcopy`, and `stty`.

## Install

```sh
git clone https://github.com/<you>/secret-keychain.git
cd secret-keychain
./install.sh          # symlinks secret-* into ~/.local/bin (override with PREFIX=)
secret-init           # creates the keychain + sets autolock (prompts for a keychain password)
```

Make sure the install dir is on your `PATH`.

## Usage

| Command | What it does |
|---|---|
| `secret-init` | Create the keychain and set its idle autolock. Run once; safe to re-run. |
| `secret-add NAME` | Store/update a secret via a no-echo prompt. |
| `secret-paste NAME` | Store a secret from the clipboard, then clear the clipboard. |
| `secret NAME` | Print a secret to stdout (for inline command substitution). |
| `secret-list` | List stored secret names — never values. |

```sh
secret-add GITHUB_TOKEN          # type the value at the hidden prompt
secret GITHUB_TOKEN              # prints the value
secret-list                     # GITHUB_TOKEN
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SECRET_KEYCHAIN` | `ai.keychain` | Keychain name used by every command. Set it to use your own. |
| `SECRET_AUTOLOCK_SECONDS` | `300` | Idle/sleep autolock timeout, applied by `secret-init`. |

To use a custom keychain, export `SECRET_KEYCHAIN` before running the commands (e.g. in your shell rc):

```sh
export SECRET_KEYCHAIN=work.keychain
secret-init
secret-add DEPLOY_KEY
```

## Security notes

- Prefer `secret-paste` for high-value credentials. `secret-add` passes the value to `security` as a
  command-line argument, so it is briefly visible in `ps` for the duration of the call (a few ms);
  `secret-paste` reads from the clipboard and avoids that argv exposure.
- The keychain autolocks after `SECRET_AUTOLOCK_SECONDS` of idle time and on sleep; macOS will prompt
  to unlock it on the next `secret` read.

## License

MIT — see [LICENSE](LICENSE).
