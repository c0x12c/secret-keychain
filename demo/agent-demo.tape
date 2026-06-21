# "Working with an AI coding agent" demo. Render from repo root with:
#   vhs demo/agent-demo.tape
#
# All the work lives in demo/agent-demo.sh, which runs the real secret-gate.sh
# hook against a throwaway keychain. This tape just records it playing out.

Output demo/secret-keychain-agent.gif

Require bash

Set Shell "bash"
Set FontSize 20
Set Width 1320
Set Height 680
Set Padding 26
Set Theme "Catppuccin Mocha"
Set TypingSpeed 8ms

Hide
Type `export PS1='$ '` Enter
Type `clear` Enter
Show

Type `bash demo/agent-demo.sh` Enter
Sleep 15s
