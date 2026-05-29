# Requirements

## Operating system

`windows-zombie` is a dual-target project: it supports **both Windows 10
and Windows 11** from a single codebase. None of the privileged surfaces
it uses (Windows Services, Scheduled Tasks, Defender Firewall, NTFS ACLs,
WinGet) are Windows 11-only.

- **Supported range:** Windows 10 build 17763 (version 1809) and newer,
  through Windows 11. The installer enforces this as a soft, warn-only
  floor — older builds print a warning but are not hard-blocked.
- **Recommended:** Windows 10 22H2 or Windows 11 22H2+ Pro or Enterprise.
- Windows 10/11 Home is supported with caveats: Group Policy and some
  firewall profile controls are reduced. This is an *edition* limitation,
  not a *version* one — it applies equally to Windows 10 Home and
  Windows 11 Home.
- Use Windows Sandbox (Windows 10 Pro 1903+ / Windows 11 Pro), Hyper-V,
  or another disposable VM for install tests.

> **Note on end-of-life.** Microsoft ended mainstream support for
> Windows 10 in October 2025. Windows 10 remains supported by this
> project on a best-effort basis; new development targets Windows 11
> first, but changes must not regress the Windows 10 build floor above.

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
