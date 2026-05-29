# CLAUDE.md

This repository uses a single source of truth for AI-agent guidance:
`AGENTS.md`. Read it before changing code or documentation.

Quick reminders:

- The project is **windows-zombie**, a Windows 10/11 installer and agent
  runtime. Use PowerShell, Windows Services, Scheduled Tasks, Defender
  Firewall, WinGet, and ACL terminology.
- Run `pwsh -File build.ps1 lint` and `pwsh -File build.ps1 test` after
  relevant changes.
- Do **not** run `scripts/Install.ps1 install`, `scripts/Uninstall.ps1`,
  or installed helpers on a non-disposable machine. They create users,
  services, firewall rules, machine environment variables, and files under
  `C:\ProgramData\AiZombie\`.
- There is no Linux-style per-command trust boundary on Windows. Privileged behaviour must
  go through `payload/agent/policy.py` and be recorded by
  `payload/agent/audit.py`.
- Keep secrets out of the repository; use placeholders such as `sk-...`.

See `AGENTS.md` for the full conventions, extension recipes, and
pre-handoff checklist.
