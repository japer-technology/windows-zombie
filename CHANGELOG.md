# Changelog

All notable changes to windows11-zombie are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- Rebranded the project and repository to `windows11-zombie` for the
  Windows 11 port.
- Replaced the Bash/systemd/sudo/apt/UFW/logrotate integration layer with
  PowerShell, Windows Services, Scheduled Tasks, WinGet, Windows Defender
  Firewall, ACL-protected `C:\ProgramData\AiZombie\` state, and built-in
  agent log rotation.
- Added `Windows11Zombie-Chat` service supervision and the
  `Windows11Zombie-Health` Scheduled Task running `Health-Check.ps1` as
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
