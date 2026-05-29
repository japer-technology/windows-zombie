# Changelog

All notable changes to windows-zombie are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed — Rename to `windows-zombie` + Windows 10/11 dual-target
- **Renamed the project and repository** from `windows11-zombie` to
  `windows-zombie` to reflect a version-neutral, dual-target identity.
  Service/task/firewall identifiers move from `Windows11Zombie-*` to
  `WindowsZombie-*`, the firewall group from `Windows11 Zombie` to
  `Windows Zombie`, the PATH shim from `windows11-zombie.cmd` to
  `windows-zombie.cmd`, and the Prometheus metrics prefix from
  `windows11_zombie_*` to `windows_zombie_*`.
- **First-class Windows 10 support.** Generalised the installer OS gate
  `Assert-Windows11` into `Assert-SupportedWindows`, which accepts
  Windows 10 build 17763 (1809) through Windows 11 with a soft, warn-only
  floor. A backwards-compatible `Assert-Windows11` alias is retained.
- **Automatic rename migration.** `Install.ps1 install`/`repair` now call
  `Remove-LegacyServiceArtifact` to stop and remove legacy
  `Windows11Zombie-*` service/tasks and the old firewall rule/group so
  in-place upgrades from `windows11-zombie` are not orphaned. User data
  under `C:\ProgramData\AiZombie\` is untouched. See
  [`docs/UPGRADE.md`](docs/UPGRADE.md).
- **Correct edition detection.** `server.py` `machine_facts()` now derives
  Windows 10 vs 11 from the OS build number (>= 22000 is Windows 11)
  instead of a brittle version-string prefix.
- Swept docs, skills, and the agent system-prompt templates to describe a
  "Windows 10 or Windows 11" target instead of "Windows 11".

### Added
- **Secrets backup-on-edit.** `payload/bin/Secrets-Edit.ps1` now writes a
  timestamped backup of `C:\ProgramData\AiZombie\secrets\env` to
  `secrets\backups\env.<UTC-stamp>` before launching the editor, with the
  same restricted ACL as the live file. The ten most recent backups are
  kept and older ones are pruned on every edit. If a save leaves the file
  empty, the helper prints a roll-back command pointing at the newest
  backup. Ported from the `ubuntu-zombie` inspiration and documented in
  `docs/CONFIGURATION.md`.

## [0.4.0] - 2026-05-28

### Changed — Platform pivot: Ubuntu → Windows 11

- Rebranded the project and repository to `windows-zombie` for the
  Windows 11 port.
- Replaced the Bash/systemd/sudo/apt/UFW/logrotate integration layer with
  PowerShell, Windows Services, Scheduled Tasks, WinGet, Windows Defender
  Firewall, ACL-protected `C:\ProgramData\AiZombie\` state, and built-in
  agent log rotation.
- Added `WindowsZombie-Chat` service supervision and the
  `WindowsZombie-Health` Scheduled Task running `Health-Check.ps1` as
  SYSTEM.
- Moved the trust model to Windows identities: `LocalSystem` by default,
  with an optional local Administrators account named `zombie` for service
  identity parity.
- Documented the Windows policy gate as the sole privileged-action
  boundary, with read-only diagnostics auto-run, mutating actions requiring
  operator approval, and destructive actions requiring an explicit
  confirmation phrase.
- Updated the agent OS-abstraction layer and documentation for Windows
  command dispatch: services, Event Log, WinGet, Defender Firewall,
  local users/groups, Tailscale, screenshots, and GUI actions.
