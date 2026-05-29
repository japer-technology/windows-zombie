# AGENTS.md

Guidance for AI coding agents working in this repository. Human
contributors should read `CONTRIBUTING.md` first; this file restates the
Windows-specific details an autonomous agent is most likely to get wrong.

## What this repository is

Windows Zombie is a PowerShell + Python/Node installer that adds a
private, policy-gated AI Systems Administrator to a Windows 10 or Windows 11 PC. The OS
integration layer is Windows Services, Scheduled Tasks, Defender Firewall,
WinGet, local users/groups, and ACL-protected files under
`C:\ProgramData\AiZombie\`. The portable agent runtime remains under
`payload/agent/`.

Read these before changing anything substantive:

- `README.md` — entry point and trust model summary.
- `docs/VISION.md` — in-scope and out-of-scope goals.
- `docs/ARCHITECTURE.md` — Windows components and trust boundaries.
- `SECURITY.md` — Windows threat model and disclosure policy.
- `CONTRIBUTING.md` — development loop and extension recipes.

## Repository layout

```text
scripts/
  Install.ps1              # elevated installer: install/verify/doctor/repair/uninstall
  Uninstall.ps1            # uninstaller wrapper
payload/
  agent/                   # portable Python/Node chat service and policy runtime
  bin/                     # PowerShell helpers (Zombie-Chat, Health-Check, ...)
  etc/policy.yaml          # default policy gate
tests/Smoke.ps1            # syntax, python, policy, subcommands, standards
build.ps1, VERSION
docs/
```

Installed machines use:

```text
C:\ProgramData\AiZombie\
  bin\ agent\ etc\ secrets\ logs\ state\ agent-env\ pi\
```

## Commands

Run from the repository root:

```powershell
pwsh -File build.ps1 lint
pwsh -File build.ps1 test
pwsh -File build.ps1 package
```

The real installer must be run from an elevated PowerShell session on a
disposable Windows 10/11 machine:

```powershell
pwsh -File scripts/Install.ps1 install
pwsh -File scripts/Install.ps1 verify
pwsh -File scripts/Install.ps1 doctor
pwsh -File scripts/Install.ps1 repair
pwsh -File scripts/Uninstall.ps1 -Archive -AssumeYes
```

Do **not** run `scripts/Install.ps1 install`, `scripts/Uninstall.ps1`, or
helpers that mutate `C:\ProgramData\AiZombie\` from an agent environment
or a workstation you are not prepared to change. Prefer Windows Sandbox or
a disposable VM.

## Non-negotiable rules

1. **Idempotence.** `Install.ps1 install` must converge on re-run. Check
   before creating users, services, tasks, firewall rules, directories,
   ACLs, or machine environment variables.
2. **Administrator boundary.** Installer and repair work require an
   elevated PowerShell session. Documentation should say "Run as
   Administrator" rather than using Linux privilege language.
3. **Policy gate + audit log.** There is no Windows per-command elevation prompt in
   this project. Any privileged or mutating behaviour must go through
   `payload/agent/policy.py` and be recorded by `payload/agent/audit.py`.
4. **No secrets in the repo.** Use placeholders such as `sk-...` in docs.
5. **No new runtime dependencies** beyond PowerShell, Python 3.12, Node.js
   20, WinGet/App Installer, and optional Tailscale unless the task
   explicitly requires it.
6. **No local state, screenshots, diagnostics, or generated archives in
   commits.**

## Windows command vocabulary

Use these replacements consistently in docs and code:

- Services: `Get-Service`, `Start-Service`, `Stop-Service`,
  `Restart-Service`, and `sc.exe` for identity configuration.
- Logs: `Get-WinEvent -LogName Application -ProviderName
  WindowsZombie-Chat -MaxEvents 50` and files under
  `C:\ProgramData\AiZombie\logs\`.
- Packages: `winget install --silent --accept-source-agreements
  --accept-package-agreements ...`.
- Firewall: `Get-NetFirewallRule`, `New-NetFirewallRule`, and the
  `Windows Zombie` rule group.
- Users: `New-LocalUser`, `Add-LocalGroupMember`, and ACL cmdlets.
- GUI: `payload/bin/Screenshot.ps1` plus `payload/bin/GuiAction.ps1`.
- Tailscale: `& 'C:\Program Files\Tailscale\tailscale.exe' up`.

## Code conventions

- **PowerShell:** keep scripts parse-clean under PowerShell 7 and Windows
  PowerShell 5.1 when they are installer entry points. Use explicit error
  handling and avoid interactive prompts unless an `-AssumeYes` or
  non-interactive path exists.
- **Python:** 4-space indent, type hints on public functions, standard
  library preferred, and `python -m compileall` clean.
- **Markdown:** wrap at roughly 78 columns and use Windows paths when
  describing this project.
- **Commits:** imperative subject under 72 characters; group related
  changes.

## Extending the system

- **New LLM provider:** implement `BaseProvider` in
  `payload/agent/providers.py`, register it in `provider_from_env()`,
  document machine env vars and `secrets\env` entries in
  `docs/CONFIGURATION.md`, and add smoke coverage if needed.
- **New policy class:** add it to `payload/etc/policy.yaml`, handle it in
  `payload/agent/policy.py`, document it in `docs/ARCHITECTURE.md`, and
  ensure audit logging records every decision.
- **New installer subcommand:** add it to `scripts/Install.ps1`, document
  it in `README.md`, and extend `tests/Smoke.ps1` subcommand checks.

## Before handing work back

- [ ] `pwsh -File build.ps1 lint` is clean when relevant.
- [ ] `pwsh -File build.ps1 test` is clean when relevant.
- [ ] If installer logic changed, idempotence and elevated Windows paths
      were re-checked.
- [ ] If `payload/agent/` changed, no privileged action bypasses policy or
      audit.
- [ ] User-facing docs and `CHANGELOG.md` reflect the change.
- [ ] No secrets, screenshots, diagnostics, local state, or generated
      packages are staged.

## Leave alone unless explicitly asked

- `VERSION`, except during a release.
- `LICENSE`, `CODE_OF_CONDUCT.md`, and disclosure contact details.
- Historical comparison material except where it names this project.
- `payload/agent/paths.py` Linux fallback comments.
- `payload/agent/templates/*.tmpl` and `payload/agent/skills/*.md` when a
  task says they are already updated.
