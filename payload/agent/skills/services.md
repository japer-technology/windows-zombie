<!-- triggers: service, sc, scheduled task, taskschd, scheduler, daemon, event log, eventvwr -->
# Skill: Windows Services and Scheduled Tasks

This skill is loaded when the operator mentions Windows Services,
Scheduled Tasks, `sc.exe`, or the Event Log.

Operating rules:

- Use `svc.status` (wraps `Get-Service`) to inspect a service before
  suggesting changes. It is `read_only` and runs automatically.
- Use `svc.control` for `start`, `stop`, `restart`, `enable`
  (sets StartupType=Automatic), and `disable` (sets StartupType=Disabled).
  It is `system_change` and requires operator approval.
- Reading the Event Log via `Get-WinEvent -LogName Application
  -MaxEvents N` is `read_only`; prefer bounded reads over
  `Get-WinEvent -Wait`. Always include a small `-MaxEvents` cap so the
  output is captured.
- Never disable `Windows11Zombie-Chat` or any service whose name
  contains `sshd`, `TermService`, or `Tailscale` without explicit
  operator approval — they are the remote-access lifeline.
- For new services prefer `sc.exe create` or `New-Service`; do not
  write directly into `HKLM:\SYSTEM\CurrentControlSet\Services\`
  without describing the change and asking the operator to land it
  through the installer.
- When restarting a service, name its dependents (use
  `Get-Service -DependentServices`) so the operator can weigh the
  blast radius before approving.
- For periodic work, Scheduled Tasks (`Register-ScheduledTask`,
  `Get-ScheduledTask`) are the systemd-timer equivalent. Mutating
  task registration is `system_change`; reading task state is
  `read_only`.
