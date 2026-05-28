# Requirements

## Operating system

- Windows 11 22H2+ Pro or Enterprise recommended.
- Windows 11 Home is supported with caveats: Group Policy and some
  firewall profile controls are reduced.
- Use Windows Sandbox, Hyper-V, or another disposable VM for install tests.

## Shell

- PowerShell 7+ (`pwsh`) for normal operation.
- Windows PowerShell 5.1 is supported for installer/bootstrap paths only.

## Package manager

- WinGet / App Installer 1.6+.

```powershell
winget --version
```

Chocolatey may be used manually by operators as a fallback, but it is not a
project requirement.

## Runtimes

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Python.Python.3.12
winget install --silent --accept-source-agreements --accept-package-agreements OpenJS.NodeJS.LTS
```

Python 3.12 is used for the agent and virtual environment. Node.js 20 LTS
is used for the pi bridge and related tooling.

## Recommended tools

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Git.Git
winget install --silent --accept-source-agreements --accept-package-agreements jqlang.jq
```

`git` and `jq` are optional but useful for operators and contributors.

## Optional remote access

```powershell
winget install --silent --accept-source-agreements --accept-package-agreements Tailscale.Tailscale
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

RDP is the default remote desktop path. Keep Network Level Authentication
enabled and restrict RDP/OpenSSH to Tailscale or trusted management
networks.
