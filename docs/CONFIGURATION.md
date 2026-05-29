# Configuration

Default root: `C:\ProgramData\AiZombie\`. Set `AI_ZOMBIE_ROOT` before
install if you need a different location.

## Machine environment variables

Set machine-wide values from an elevated PowerShell session:

```powershell
[System.Environment]::SetEnvironmentVariable('ZOMBIE_PROVIDER', 'openai', 'Machine')
[System.Environment]::SetEnvironmentVariable('ZOMBIE_MODEL', 'gpt-4.1', 'Machine')
[System.Environment]::SetEnvironmentVariable('AI_ZOMBIE_ROOT', 'C:\ProgramData\AiZombie', 'Machine')
Restart-Service Windows11Zombie-Chat
```

Service processes read machine environment at start, so restart
`Windows11Zombie-Chat` after changes.

## Secrets file

Secrets live at:

```text
C:\ProgramData\AiZombie\secrets\env
```

Use:

```powershell
pwsh -File .\payload\bin\Secrets-Edit.ps1
```

The helper opens Notepad++ when available and falls back to Notepad. It
then disables inheritance, grants FullControl to `BUILTIN\Administrators`,
`NT AUTHORITY\SYSTEM`, and `zombie`, and logs a SHA-256 audit entry.

Before the editor opens, a timestamped backup of the current secrets file
is written to `C:\ProgramData\AiZombie\secrets\backups\env.<UTC-stamp>`
with the same restricted ACL. The ten most recent backups are kept and
older ones are pruned on each edit. If a save leaves the file empty, the
helper prints a roll-back command pointing at the newest backup.

DPAPI encryption can be layered on by operators who require host-bound
secret protection. The default is ACL'd plaintext for transparent recovery
and parity with the legacy Unix file mode model.

## Policy

Edit `C:\ProgramData\AiZombie\etc\policy.yaml` to change approvals,
budgets, destructive confirmation phrases, or tool classes. Keep unknown
or risky commands fail-closed. Any new privileged capability must be
classified in policy and audited.

## Agent settings

- `C:\ProgramData\AiZombie\etc\settings.json` controls runtime defaults.
- `C:\ProgramData\AiZombie\etc\APPEND_SYSTEM.md` appends local system
  prompt guidance.
- `C:\ProgramData\AiZombie\etc\skills.d\` stores local skills.
- `C:\ProgramData\AiZombie\pi\settings.json` configures the Node/pi
  bridge.

Restart the service after edits:

```powershell
Restart-Service Windows11Zombie-Chat
```

## Service identity

Default identity is `LocalSystem`. To run as the dedicated local
Administrators account `zombie`:

```powershell
sc.exe config Windows11Zombie-Chat obj= .\zombie password= <password>
Restart-Service Windows11Zombie-Chat
```

To return to LocalSystem:

```powershell
sc.exe config Windows11Zombie-Chat obj= LocalSystem
Restart-Service Windows11Zombie-Chat
```

The `zombie` account gives a named ACL and audit identity, but it remains
an administrator. The policy gate is still the security boundary.

## Firewall

Inspect the project rule group:

```powershell
Get-NetFirewallRule -Group 'Windows11 Zombie'
```

Create additional scoped rules with `New-NetFirewallRule -Group 'Windows11
Zombie' ...`. Keep chat bound to loopback and restrict RDP/OpenSSH to
Tailscale or trusted management networks.
