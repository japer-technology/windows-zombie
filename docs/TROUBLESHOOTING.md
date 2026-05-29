# Troubleshooting

Run diagnostics first from an elevated PowerShell session:

```powershell
pwsh -File scripts/Install.ps1 doctor
pwsh -File scripts/Install.ps1 verify
Get-Service WindowsZombie-Chat
Get-ScheduledTask WindowsZombie-Health
Get-Content C:\ProgramData\AiZombie\logs\install.log -Tail 100
Get-Content C:\ProgramData\AiZombie\logs\audit.log -Tail 100
```

## PowerShell execution policy blocks scripts

For the current elevated shell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
pwsh -File scripts/Install.ps1 install
```

## Defender SmartScreen or antivirus blocks files

Unsigned scripts, downloaded archives, `python.exe`, or Node subprocesses
may be quarantined. Prefer a narrow allow rule for the checkout and
`C:\ProgramData\AiZombie\` rather than disabling protection globally.
Check Windows Security history before retrying.

## WinGet is missing

Install or update **App Installer** from Microsoft Store, then verify:

```powershell
winget --version
```

The project expects App Installer / WinGet 1.6+.

## Runtime packages are missing

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Python.Python.3.12
winget install --silent --accept-source-agreements --accept-package-agreements OpenJS.NodeJS.LTS
```

Restart PowerShell after PATH changes.

## Service did not start in a timely fashion

Inspect service configuration and recent events:

```powershell
sc.exe query WindowsZombie-Chat
sc.exe qc WindowsZombie-Chat
Get-WinEvent -LogName Application -ProviderName WindowsZombie-Chat -MaxEvents 50
Get-Content C:\ProgramData\AiZombie\logs\chat.log -Tail 100
```

Then repair and restart:

```powershell
pwsh -File scripts/Install.ps1 repair
Restart-Service WindowsZombie-Chat
```

## Firewall profile mismatch

Windows may classify the active network as Public. Inspect profiles and the
project rule group:

```powershell
Get-NetConnectionProfile
Get-NetFirewallProfile
Get-NetFirewallRule -Group 'Windows Zombie'
```

Keep chat loopback-only. Scope RDP/OpenSSH rules to Tailscale or trusted
remote addresses.

## Tailscale is not reachable

Verify the Windows service and CLI:

```powershell
Get-Service Tailscale
& 'C:\Program Files\Tailscale\tailscale.exe' status
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

Run `tailscale.exe up` from an elevated shell when changing machine-wide
network state.

## Local user cmdlets fail

`New-LocalUser` and `Add-LocalGroupMember` require Windows PowerShell 5.1+
or PowerShell 7 on Windows. They are unavailable on non-Windows hosts and
some constrained enterprise images. Use a standard Windows 10/11 Pro or
Enterprise VM for install testing.

## GUI tools do not render

Scheduled Tasks running as SYSTEM do not have the operator's interactive
desktop. `Screenshot.ps1` and `GuiAction.ps1` require an interactive
session, or a service identity/session arrangement that can access the
desktop. Prefer RDP into the machine before attempting GUI actions.

## Secrets edits lose ACLs

Always use:

```powershell
pwsh -File .\payload\bin\Secrets-Edit.ps1
```

If ACLs drift, run:

```powershell
pwsh -File scripts/Install.ps1 repair
```

## Collect diagnostics

```powershell
pwsh -File .\payload\bin\Collect-Diagnostics.ps1
```

Review the bundle before sharing it; remove secrets, private prompts, and
hostnames as needed.
