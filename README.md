# windows11-zombie

<p align="center">
  <img src="https://raw.githubusercontent.com/japer-technology/windows11-zombie/main/LOGO.png" alt="Windows 11 Zombie" width="500">
</p>

> **Windows 11 Zombie adds a private, policy-gated AI Systems
> Administrator to Microsoft Windows 11.** It installs a local chat
> daemon, a portable Python/Node agent runtime, Windows Service
> supervision, Defender Firewall rules, and ACL-protected state under
> `C:\ProgramData\AiZombie\`.

The project targets **Windows 11 22H2+ Pro or Enterprise**. Windows 11
Home can run the agent, but Group Policy and some firewall profile controls
are reduced. The service runs as `LocalSystem` by default, while the
installer also creates a local Administrators account named `zombie` for
operators who want a dedicated service identity.

Repository: <https://github.com/japer-technology/windows11-zombie>

## What it installs

- `Windows11Zombie-Chat`, an auto-starting Windows Service with restart on
  failure.
- `Windows11Zombie-Health`, a Scheduled Task that runs
  `Health-Check.ps1` as SYSTEM every five minutes.
- `C:\ProgramData\AiZombie\` containing `bin\`, `agent\`, `etc\`,
  `secrets\`, `logs\`, `state\`, `agent-env\`, and `pi\`.
- A machine-wide `windows11-zombie.cmd` shim on `PATH` that launches
  `payload/bin/Zombie-Chat.ps1`.
- A `Windows11 Zombie` Windows Defender Firewall rule group. The chat
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

- Windows 11 22H2+ Pro or Enterprise recommended.
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
git clone https://github.com/japer-technology/windows11-zombie.git
cd windows11-zombie
pwsh -File scripts/Install.ps1 install
pwsh -File scripts/Install.ps1 verify
windows11-zombie.cmd
```

The helper prints the local chat URL. By default the web UI listens on
`http://127.0.0.1:7878/`; use RDP or a Tailscale tunnel from a trusted
operator machine rather than exposing the port directly.

Common lifecycle commands:

```powershell
pwsh -File scripts/Install.ps1 doctor
pwsh -File scripts/Install.ps1 repair
Restart-Service Windows11Zombie-Chat
Get-Service Windows11Zombie-Chat
Get-WinEvent -LogName Application -ProviderName Windows11Zombie-Chat -MaxEvents 50
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
Restart-Service Windows11Zombie-Chat
```

Use `payload/bin/Secrets-Edit.ps1` to edit secrets; it re-applies ACLs and
logs a SHA-256 audit entry. DPAPI encryption is a planned stronger option,
but ACL'd plaintext is the default for parity with the legacy `0640` file.

To run the service as the dedicated `zombie` account instead of
`LocalSystem`:

```powershell
sc.exe config Windows11Zombie-Chat obj= .\zombie password= <password>
Restart-Service Windows11Zombie-Chat
```

## Development

The repository uses PowerShell build targets and CI runs on
`windows-latest`:

```powershell
pwsh -File build.ps1 lint
pwsh -File build.ps1 test
pwsh -File build.ps1 package
```

Do not run the installer, uninstaller, or service helpers on a workstation
you are not prepared to modify. Use Windows Sandbox, a disposable Hyper-V
VM, or another throwaway Windows 11 test machine.

See `docs/QUICKSTART.md`, `docs/CONFIGURATION.md`,
`docs/ARCHITECTURE.md`, and `SECURITY.md` for deeper operational details.
