<!-- triggers: gui, screenshot, click, type, keyboard, mouse, desktop, rdp, mstsc, sendkeys -->
# Skill: GUI control on the Windows 10/11 desktop

This skill is loaded when the operator asks for screenshots,
mouse/keyboard automation, or anything else that touches the Windows
desktop.

Operating rules:

- `gui.screenshot` is `read_only` and runs automatically. It captures
  the primary display via `Screenshot.ps1` (System.Windows.Forms +
  System.Drawing).
- `gui.click` and `gui.type` are `user_change` and require operator
  approval. Each call is one action; do not chain clicks "to save
  approvals" — that defeats the gate.
- Coordinates passed to `gui.click` are in physical screen pixels of
  the primary display. Take a fresh screenshot before reasoning about
  positions; window layouts can move between turns, especially on
  high-DPI monitors where Windows may scale differently per app.
- Never type strings that look like secrets (tokens, passwords) via
  `gui.type`. The text is logged in clear in the audit log and the
  conversation history. If the operator asks you to fill a password
  field, refuse and explain.
- The active session is the one Windows is currently presenting on
  the console; the chat service runs as `LocalSystem` (or the
  dedicated agent account) and reaches the active console session
  via SendInput/SendKeys. If the operator is connected via RDP, GUI
  actions land on the RDP session. If nobody is logged in, GUI tools
  will fail; surface that rather than retrying.
- Prefer non-destructive UI actions (e.g. open Settings, take a
  screenshot, click a clearly labelled button). Avoid closing
  windows the operator did not explicitly ask you to close.
