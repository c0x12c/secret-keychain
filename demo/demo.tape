# secret-keychain demo. Render with:  vhs demo/demo.tape  (run from repo root)
#
# Self-contained: it creates a throwaway keychain, runs the real tools against
# it, then the wrapper deletes the keychain. Your real ai.keychain is untouched.

Output demo/secret-keychain.gif

Require secret-add

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 600
Set Padding 26
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

# ── setup (not recorded) ───────────────────────────────────────────────
Hide
Type `export PS1='$ '` Enter
Type `export PATH="$PWD/bin:$PATH"` Enter
Type `export SECRET_KEYCHAIN="$HOME/sk-demo.keychain"` Enter
Type `security delete-keychain "$SECRET_KEYCHAIN" 2>/dev/null; security create-keychain -p demo "$SECRET_KEYCHAIN"` Enter
Type `security unlock-keychain -p demo "$SECRET_KEYCHAIN"; security set-keychain-settings "$SECRET_KEYCHAIN"` Enter
Type `source demo/_demo-helpers.sh` Enter
Type `clear` Enter
Show

# ── 1. store a secret (hidden prompt - typing is never echoed) ─────────
Type `# store a secret once - the prompt is hidden, your typing never shows` Enter
Sleep 500ms
Type "secret-add DEMO_TOKEN" Enter
Sleep 500ms
Type "sk-live-9f3a2b-illustrative-only" Enter
Sleep 1s

# ── 2. list names (never values) ──────────────────────────────────────
Type `# list what's stored - names only, never values` Enter
Sleep 400ms
Type "secret-list" Enter
Sleep 1200ms

# ── 3. use it inline - only the *name* is ever typed ──────────────────
Type `# drop it into any command - the value resolves inside the child process` Enter
Sleep 500ms
Type `curl -H "Authorization: Bearer $(secret DEMO_TOKEN)" https://api.acme.dev/me` Enter
Sleep 1600ms

# ── 4. proof: the value never persists in your shell or environment ───
Type `# and it never lingers - it was never exported, never written to disk:` Enter
Sleep 500ms
Type `printenv DEMO_TOKEN || echo "(unset - it existed only inside that one command)"` Enter
Sleep 2600ms
