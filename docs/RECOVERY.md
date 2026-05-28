# Recovery

Recovery procedures for the most common failures of a single
`windows11-zombie` deployment. Pair with
[`OPERATIONS.md`](OPERATIONS.md) and [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

All commands assume an elevated PowerShell session.

## Restore from an archive

`Uninstall.ps1 -Archive` and `Install.ps1 backup` both produce a zip
under `C:\ProgramData\AiZombie-backups\` or
`C:\ProgramData\AiZombie\state\backups\` respectively. Restore is:

```powershell
pwsh -File scripts/Install.ps1 restore -Path <path-to-zip>
pwsh -File scripts/Install.ps1 verify
Restart-Service Windows11Zombie-Chat
```

`restore` verifies a `SHA256SUMS` manifest inside the zip, lays the
files back into their original locations, and re-applies ACLs. It
will refuse to overwrite a live install unless `-Force` is passed.

## Disaster scenarios

### Corrupt `conversations.db`

Symptom: chat UI returns 500; service log shows
`sqlite3.DatabaseError: database disk image is malformed`.

```powershell
Stop-Service Windows11Zombie-Chat
Move-Item C:\ProgramData\AiZombie\state\conversations.db `
          C:\ProgramData\AiZombie\state\conversations.db.bad
Start-Service Windows11Zombie-Chat
```

The agent recreates the database on next start (an empty history is
the only data loss). The startup integrity check
(`PRAGMA integrity_check`) does the move automatically in newer
builds; the manual procedure above is the fallback.

### Lost or accidentally-deleted `secrets\env`

```powershell
pwsh -File scripts/Install.ps1 repair
notepad C:\ProgramData\AiZombie\secrets\env
Restart-Service Windows11Zombie-Chat
```

`repair` lays down a fresh template and re-applies the ACL. Paste
the provider key into the new file.

### Broken Python venv

```powershell
Remove-Item -Recurse -Force C:\ProgramData\AiZombie\agent-env
pwsh -File payload/bin/Setup-AgentVenv.ps1 -VenvDir C:\ProgramData\AiZombie\agent-env
Restart-Service Windows11Zombie-Chat
```

`Install.ps1 repair` will also rebuild the venv when
`python -c "import sys"` fails.

### Wedged service

```powershell
Get-Service Windows11Zombie-Chat
sc.exe queryex Windows11Zombie-Chat
Stop-Service Windows11Zombie-Chat -Force
Start-Service Windows11Zombie-Chat
```

If `Stop-Service` cannot complete:

```powershell
$pid = (sc.exe queryex Windows11Zombie-Chat | Select-String "PID").ToString().Split(':')[1].Trim()
Stop-Process -Id $pid -Force
Start-Service Windows11Zombie-Chat
```

### Firewall rule drift

```powershell
Get-NetFirewallRule -Group 'Windows11 Zombie'   # should list the deny rule
pwsh -File scripts/Install.ps1 repair
```

If the chat port has somehow become reachable off-host, the
`Health-Check` task detects a non-loopback bind and refuses to mark
the install healthy.

### Tailscale offline

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' status
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

The chat service does not depend on Tailscale at runtime; the
`Health-Check` task downgrades to a warning rather than a failure
when Tailscale is offline.

### Disk full

`Health-Check.ps1` marks the install unhealthy when free space falls
below 1 GB. Free space, then:

```powershell
pwsh -File payload/bin/Health-Check.ps1
Restart-Service Windows11Zombie-Chat
```

Old audit log files are rotated in-place; if `logs\` itself has
filled the volume, prune the oldest `audit.log.*` rotations.

### Audit log tampering

```powershell
pwsh -File payload/bin/Verify-Audit.ps1
```

A non-zero exit code means the hash chain in `logs\audit.log` does
not validate. Preserve the file as evidence and rotate to a fresh
audit log:

```powershell
Move-Item C:\ProgramData\AiZombie\logs\audit.log `
          C:\ProgramData\AiZombie\logs\audit.log.tamper-$(Get-Date -Format yyyyMMdd-HHmmss)
Restart-Service Windows11Zombie-Chat
```

### Lost local `zombie` account

```powershell
pwsh -File scripts/Install.ps1 repair
```

`repair` recreates the account if missing and re-adds it to the
Administrators group.

## Disaster drill

Schedule a quarterly drill to prove recovery actually works:

1. `Install.ps1 backup`
2. `Uninstall.ps1 -Archive -AssumeYes`
3. `Install.ps1 install`
4. `Install.ps1 restore -Path <backup-zip>`
5. `Install.ps1 verify`
6. Open the chat UI and submit a no-op prompt.

Record the elapsed wall-clock time so you can spot regressions.
