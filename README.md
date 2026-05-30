# windows-zombie

<p align="center">
  <img src="https://raw.githubusercontent.com/japer-technology/windows-zombie/main/LOGO.png" alt="Windows Zombie" width="500">
</p>

<p align="center">
  <a href="https://github.com/japer-technology/windows-zombie/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/japer-technology/windows-zombie/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/japer-technology/windows-zombie/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/japer-technology/windows-zombie?display_name=tag&sort=semver"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/japer-technology/windows-zombie"></a>
  <a href="SECURITY.md"><img alt="Security policy" src="https://img.shields.io/badge/security-policy-blue"></a>
  <a href="https://securityscorecards.dev/viewer/?uri=github.com/japer-technology/windows-zombie"><img alt="OpenSSF Scorecard" src="https://api.securityscorecards.dev/projects/github.com/japer-technology/windows-zombie/badge"></a>
</p>

> **Windows Zombie adds a private, policy-gated AI Systems
> Administrator to Microsoft Windows 10 and 11.** It installs a local chat
> daemon, a portable Python/Node agent runtime, Windows Service
> supervision, Defender Firewall rules, and ACL-protected state under
> `C:\ProgramData\AiZombie\`.

## Why?

Running an AI agent that can actually administer your Windows host
means giving it real privileges. Most "AI assistant" projects either
sandbox themselves into uselessness or hand the model a root shell
with no audit trail. Windows Zombie takes the middle path: full
local capability, gated by an **editable, auditable policy** with
explicit operator approval for anything mutating and a confirmation
phrase for anything destructive. The chat UI is loopback-only; the
only outbound traffic is to the provider you chose.

The project targets **Windows 10 22H2 or Windows 11 22H2+ Pro or Enterprise**. Windows 10/11
Home can run the agent, but Group Policy and some firewall profile controls
are reduced. The service runs as `LocalSystem` by default, while the
installer also creates a local Administrators account named `zombie` for
operators who want a dedicated service identity.

Repository: <https://github.com/japer-technology/windows-zombie>

> ⚠️ **Production checklist.** Read [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md)
> and [`docs/OPERATIONS.md`](docs/OPERATIONS.md) before installing on
> any machine you care about. The [`docs/INDEX.md`](docs/INDEX.md)
> landing page maps every operator/security/contributor task to the
> right doc.

## What it installs

- `WindowsZombie-Chat`, an auto-starting Windows Service with restart on
  failure.
- `WindowsZombie-Health`, a Scheduled Task that runs
  `Health-Check.ps1` as SYSTEM every 15 minutes.
- `C:\ProgramData\AiZombie\` containing `bin\`, `agent\`, `etc\`,
  `secrets\`, `logs\`, `state\`, `agent-env\`, and `pi\`.
- A machine-wide `windows-zombie.cmd` shim on `PATH` that launches
  `payload/bin/Zombie-Chat.ps1`.
- A `Windows Zombie` Windows Defender Firewall rule group. The chat
  port (`7878`) binds to loopback only and is denied from other
  interfaces. RDP and optional OpenSSH should be restricted to Tailscale.
- An ACL-protected plaintext secrets file at
  `C:\ProgramData\AiZombie\secrets\env`.

There is no Linux privilege prompt, Linux service manager, Linux firewall frontend, Linux package manager, or external log-rotation daemon on Windows. The
policy engine in `payload/etc/policy.yaml` is the sole privilege gate:
read-only diagnostics may auto-run, mutating actions need operator
approval, and destructive actions require an explicit confirmation phrase.
The agent rotates JSONL audit logs itself under `logs\`.

## Requirements

- Windows 10 22H2 or Windows 11 22H2+ Pro or Enterprise recommended.
- PowerShell 7+ (`pwsh`) for normal operation. Windows PowerShell 5.1 is
  supported only for bootstrap compatibility.
- WinGet / App Installer 1.6+.
- Python 3.12, Node.js 20, and optional Tailscale. The installer can use
  WinGet to install missing runtimes:

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Python.Python.3.12
winget install --silent --accept-source-agreements --accept-package-agreements OpenJS.NodeJS.LTS
winget install --silent --accept-source-agreements --accept-package-agreements Tailscale.Tailscale
```

## Quick start

Open **PowerShell as Administrator** and run:

```powershell
git clone https://github.com/japer-technology/windows-zombie.git
cd windows-zombie
pwsh -File scripts/Install.ps1 install
pwsh -File scripts/Install.ps1 verify
windows-zombie.cmd
```

The helper prints the local chat URL. By default the web UI listens on
`http://127.0.0.1:7878/`; use RDP or a Tailscale tunnel from a trusted
operator machine rather than exposing the port directly.

Common lifecycle commands:

```powershell
pwsh -File scripts/Install.ps1 doctor
pwsh -File scripts/Install.ps1 repair
Restart-Service WindowsZombie-Chat
Get-Service WindowsZombie-Chat
Get-WinEvent -LogName Application -ProviderName WindowsZombie-Chat -MaxEvents 50
Get-Content C:\ProgramData\AiZombie\logs\audit.log -Tail 50
pwsh -File scripts/Uninstall.ps1 -Archive -AssumeYes
```

To bring up Tailscale on Windows:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

## Configuration

Primary configuration lives under `C:\ProgramData\AiZombie\etc\`:

- `policy.yaml` defines tool classes, approvals, budgets, and destructive
  confirmation rules.
- `settings.json` and `APPEND_SYSTEM.md` override agent behaviour.
- `skills.d\` contains operator skill documents.
- `secrets\env` stores provider tokens and other secrets with inheritance
  disabled and FullControl granted only to Administrators, SYSTEM, and
  `zombie`.

Machine environment variables can be set with:

```powershell
[System.Environment]::SetEnvironmentVariable('ZOMBIE_PROVIDER', 'openai', 'Machine')
[System.Environment]::SetEnvironmentVariable('AI_ZOMBIE_ROOT', 'C:\ProgramData\AiZombie', 'Machine')
Restart-Service WindowsZombie-Chat
```

Use `payload/bin/Secrets-Edit.ps1` to edit secrets; it re-applies ACLs and
logs a SHA-256 audit entry. DPAPI encryption is a planned stronger option,
but ACL'd plaintext is the default for parity with the legacy `0640` file.

To run the service as the dedicated `zombie` account instead of
`LocalSystem`:

```powershell
sc.exe config WindowsZombie-Chat obj= .\zombie password= <password>
Restart-Service WindowsZombie-Chat
```

## Development

Inspired by https://github.com/japer-technology/ubuntu-zombie

The repository uses PowerShell build targets and CI runs on
`windows-latest`:

```powershell
pwsh -File build.ps1 lint
pwsh -File build.ps1 test
pwsh -File build.ps1 package
```

Do not run the installer, uninstaller, or service helpers on a workstation
you are not prepared to modify. Use Windows Sandbox, a disposable Hyper-V
VM, or another throwaway Windows 10/11 test machine.

See `docs/QUICKSTART.md`, `docs/CONFIGURATION.md`,
`docs/ARCHITECTURE.md`, and `SECURITY.md` for deeper operational details.
