# Quickstart

This guide installs windows11-zombie on a Windows 11 PC.

## 1. Start an elevated shell

Open **PowerShell as Administrator**. If execution policy blocks local
scripts for this process, use:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## 2. Clone and install

```powershell
git clone https://github.com/japer-technology/windows11-zombie.git
cd windows11-zombie
pwsh -File scripts/Install.ps1 install
```

The installer creates `C:\ProgramData\AiZombie\`, installs or verifies the
portable runtime, creates the `zombie` administrator account, registers the
`Windows11Zombie-Chat` service, registers the `Windows11Zombie-Health`
Scheduled Task, and configures the `Windows11 Zombie` Defender Firewall
rule group.

## 3. Verify

```powershell
pwsh -File scripts/Install.ps1 verify
Get-Service Windows11Zombie-Chat
Get-ScheduledTask Windows11Zombie-Health
Get-NetFirewallRule -Group 'Windows11 Zombie'
```

## 4. Configure secrets

```powershell
pwsh -File .\payload\bin\Secrets-Edit.ps1
Restart-Service Windows11Zombie-Chat
```

The secrets file is `C:\ProgramData\AiZombie\secrets\env`. The helper
re-applies ACLs and records a SHA-256 audit entry.

## 5. Open chat

```powershell
windows11-zombie.cmd
```

The helper prints the local URL, normally `http://127.0.0.1:7878/`. Use
RDP or Tailscale to reach the desktop; do not expose the chat port on a
network interface.

## 6. Remote access

RDP is the default remote desktop path. Keep Network Level Authentication
enabled and restrict `3389` to Tailscale or a trusted management network.
For Tailscale:

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Tailscale.Tailscale
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

## Lifecycle commands

```powershell
pwsh -File scripts/Install.ps1 doctor
pwsh -File scripts/Install.ps1 repair
Restart-Service Windows11Zombie-Chat
Stop-Service Windows11Zombie-Chat
Start-Service Windows11Zombie-Chat
Get-WinEvent -LogName Application -ProviderName Windows11Zombie-Chat -MaxEvents 50
Get-Content C:\ProgramData\AiZombie\logs\audit.log -Tail 50
pwsh -File scripts/Uninstall.ps1 -Archive -AssumeYes
```

`Uninstall.ps1` also supports `-KeepAgent` when you want to remove service
plumbing but leave agent state in place.
