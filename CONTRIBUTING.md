# Contributing

Thank you for improving windows-zombie. The project is a Windows 10/11
installer plus a portable Python/Node agent runtime, so changes should be
small, reviewable, and safe to validate on disposable Windows machines.

## Development loop

From the repository root:

```powershell
pwsh -File build.ps1 help
pwsh -File build.ps1 lint
pwsh -File build.ps1 test
pwsh -File build.ps1 package
```

`lint` parses PowerShell, compiles Python, and parses `policy.yaml`.
`test` runs `tests/Smoke.ps1 all`. CI runs on `windows-latest`.

Use Windows Sandbox, a Hyper-V VM, or another throwaway Windows 10 22H2 or Windows 11 22H2+
Pro/Enterprise machine for real installs. Do not run the installer or
uninstaller on a machine you are not prepared to modify.

## Installer rules

`scripts/Install.ps1` supports `install`, `verify`, `doctor`, `repair`,
and `uninstall`. It must be idempotent: re-running `install` should
converge without duplicate users, services, tasks, firewall rules, ACLs,
or PATH entries.

The installer is expected to run from an elevated PowerShell session
("Run as Administrator"). Missing prerequisites should produce actionable
errors and, where appropriate, WinGet commands using:

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements <Package.Id>
```

## Security invariants

- The service is `WindowsZombie-Chat`; health supervision is the
  `WindowsZombie-Health` Scheduled Task.
- Installed state lives under `C:\ProgramData\AiZombie\` unless
  `AI_ZOMBIE_ROOT` overrides it.
- The local `zombie` account is a member of Administrators. The service
  may run as `LocalSystem` or `zombie`.
- There is no Linux-style per-command elevation prompt. `payload/etc/policy.yaml`,
  `payload/agent/policy.py`, and `payload/agent/audit.py` are the
  privilege and accountability boundary.
- Secrets stay out of git. Use `C:\ProgramData\AiZombie\secrets\env` and
  `payload/bin/Secrets-Edit.ps1`.

## Documentation rules

When a user-visible behaviour changes, update the relevant docs and add a
`CHANGELOG.md` entry. Use Windows terms and paths:

- `Get-Service` / `Restart-Service` / `sc.exe` for services;
- `Get-WinEvent` and `C:\ProgramData\AiZombie\logs\` for logs;
- Defender Firewall cmdlets for network rules;
- WinGet for packages;
- `Screenshot.ps1` and `GuiAction.ps1` for GUI automation.

## Extension recipes

### New provider

Implement `BaseProvider` in `payload/agent/providers.py`, register it in
`provider_from_env()`, document environment variables and secrets in
`docs/CONFIGURATION.md`, and add smoke coverage when practical.

### New policy class

Add the class to `payload/etc/policy.yaml`, implement classification in
`payload/agent/policy.py`, describe it in `docs/ARCHITECTURE.md`, and make
sure audit entries include the decision.

### New helper or installer subcommand

Add the PowerShell helper under `payload/bin/` or the subcommand in
`scripts/Install.ps1`, then update `README.md`, `docs/QUICKSTART.md`, and
`tests/Smoke.ps1` if the command surface changed.

## Pull request checklist

- [ ] `pwsh -File build.ps1 lint` passes when code changed.
- [ ] `pwsh -File build.ps1 test` passes when code changed.
- [ ] Documentation reflects user-visible changes.
- [ ] `CHANGELOG.md` has an entry.
- [ ] No secrets, local state, screenshots, diagnostics, or generated
      archives are included.
