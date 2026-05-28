# Operations runbook

Day-two operations for `windows11-zombie`. Pair this with
[`RECOVERY.md`](RECOVERY.md) for disaster scenarios and
[`UPGRADE.md`](UPGRADE.md) for in-place version bumps.

All commands assume an elevated PowerShell session
(`Run as Administrator`).

## Service lifecycle

### Status

```powershell
Get-Service Windows11Zombie-Chat
Get-ScheduledTask Windows11Zombie-Health
Get-ScheduledTask Windows11Zombie-Backup
```

### Restart

```powershell
Restart-Service Windows11Zombie-Chat
```

### Drain / quiesce before maintenance

The chat service has no long-lived sessions worth draining; in-flight
pi-mono tool calls finish or are interrupted on stop. The "quiesce"
procedure is:

```powershell
Stop-Service Windows11Zombie-Chat
# do the work
Start-Service Windows11Zombie-Chat
pwsh -File scripts/Install.ps1 verify
```

The Scheduled Task runs every 15 minutes and restarts a stopped
service. Disable the task during long maintenance windows:

```powershell
Disable-ScheduledTask -TaskName Windows11Zombie-Health
# ... do the work ...
Enable-ScheduledTask  -TaskName Windows11Zombie-Health
```

### Switch service identity (LocalSystem ↔ `zombie`)

```powershell
sc.exe config Windows11Zombie-Chat obj= .\zombie password= <password>
Restart-Service Windows11Zombie-Chat
```

To go back:

```powershell
sc.exe config Windows11Zombie-Chat obj= LocalSystem
Restart-Service Windows11Zombie-Chat
```

## Secrets

### Rotate the provider key

```powershell
pwsh -File payload/bin/Secrets-Edit.ps1
Restart-Service Windows11Zombie-Chat
```

`Secrets-Edit.ps1` re-applies ACLs and writes a SHA-256 audit entry
on each save.

### Swap providers

Set the provider preference in `C:\ProgramData\AiZombie\secrets\env`:

```text
ZOMBIE_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

…or as a machine env var:

```powershell
[System.Environment]::SetEnvironmentVariable('ZOMBIE_PROVIDER', 'anthropic', 'Machine')
Restart-Service Windows11Zombie-Chat
```

### Verify the audit chain

```powershell
pwsh -File payload/bin/Verify-Audit.ps1
```

Returns a non-zero exit code if the hash chain in
`logs\audit.log` has been tampered with.

## Logs

| Path | Purpose | Rotation |
| --- | --- | --- |
| `C:\ProgramData\AiZombie\logs\audit.log` | JSONL audit, hash-chained. | In-process size+count. |
| `C:\ProgramData\AiZombie\logs\install.log` | Installer transcript. | Append. |
| `C:\ProgramData\AiZombie\logs\events.log` | Non-audit operational events. | In-process size+count. |
| `C:\ProgramData\AiZombie\state\health.json` | Last `Health-Check.ps1` result. | Overwritten each run. |
| `Get-WinEvent -LogName Application -ProviderName Windows11Zombie-Chat` | Service start/stop, mirrored critical audit. | Standard Windows. |

Quick tail:

```powershell
Get-Content C:\ProgramData\AiZombie\logs\audit.log -Tail 50 -Wait
```

## Backups

A `Windows11Zombie-Backup` Scheduled Task runs daily and writes a
timestamped zip under `state\backups\`. Force a backup now:

```powershell
pwsh -File scripts/Install.ps1 backup
```

Restore (see [`RECOVERY.md`](RECOVERY.md) for full procedure):

```powershell
pwsh -File scripts/Install.ps1 restore -Path C:\ProgramData\AiZombie\state\backups\windows11-zombie-state-20260101-030000.zip
```

## Health

```powershell
pwsh -File payload/bin/Health-Check.ps1
Get-Content C:\ProgramData\AiZombie\state\health.json
```

The structured `health.json` is machine-readable for scraping:

```json
{ "ts_utc": "...", "ok": true, "checks": [ { "name": "...", "status": "ok|warn|fail" } ] }
```

## Firewall

The `Windows11 Zombie` rule group must contain the
"deny remote inbound" rule for the chat port:

```powershell
Get-NetFirewallRule -Group 'Windows11 Zombie'
```

Re-apply if missing:

```powershell
pwsh -File scripts/Install.ps1 repair
```

## Approvals

Mutating tool calls queue in the chat UI and require operator
approval. Destructive tool calls additionally require a confirmation
phrase set in `policy.yaml`. See [`POLICY.md`](POLICY.md).

## Diagnostic bundles

When filing a bug:

```powershell
pwsh -File payload/bin/Collect-Diagnostics.ps1
```

The redacted bundle is written under `$env:TEMP` — review before
sharing.
