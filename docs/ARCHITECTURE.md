# Architecture

windows-zombie is split into a Windows integration layer and a portable
agent runtime.

## Component overview

```text
Operator over RDP/Tailscale
        |
        v
127.0.0.1:7878 chat UI
        |
WindowsZombie-Chat Windows Service
        |
portable Python agent + Node/pi bridge
        |
policy.yaml -> approvals -> audited tool dispatch
        |
PowerShell helpers / WinGet / Services / Defender Firewall / GUI tools
```

A separate Scheduled Task, `WindowsZombie-Health`, runs
`Health-Check.ps1` as SYSTEM every 15 minutes and restarts or reports on
unhealthy service state.

## Installed layout

Default root: `C:\ProgramData\AiZombie\` (override with `AI_ZOMBIE_ROOT`).

| Path | Purpose |
| --- | --- |
| `bin\` | Installed helper scripts and `windows-zombie.cmd` target. |
| `agent\` | Portable Python/Node agent runtime. |
| `etc\policy.yaml` | Policy classes, budgets, approvals, confirmation rules. |
| `etc\skills.d\` | Operator skill documents. |
| `etc\settings.json` | Agent settings overrides. |
| `etc\APPEND_SYSTEM.md` | Extra system prompt text. |
| `secrets\env` | ACL-protected plaintext secrets. |
| `logs\audit.log` | JSONL audit log with built-in rotation. |
| `logs\install.log` | Installer transcript/log. |
| `state\conversations.db` | SQLite conversation history. |
| `state\pi-mono-sessions\` | Node/pi session state. |
| `agent-env\` | Python virtual environment. |
| `pi\settings.json` | pi bridge settings. |

## Windows services and tasks

`WindowsZombie-Chat` is an auto-start Windows Service with restart on
failure. It runs as `LocalSystem` by default. Operators may switch it to
`.\zombie` with `sc.exe config` if they prefer a named administrator
identity.

`WindowsZombie-Health` is a Scheduled Task running as SYSTEM with a
five-minute repetition interval. It calls `payload/bin/Health-Check.ps1`.
Scheduled Task context has no interactive desktop, so GUI automation only
works when run in an interactive operator session or when the service is
configured for that environment.

## Policy and tool dispatch

Windows does not provide this project a Linux-style per-command elevation prompt. The policy engine is
the privilege gate. Tool calls are classified as read-only, user change,
system change, network change, or destructive. Read-only diagnostics can
auto-run, mutating operations require approval, and destructive operations
require an explicit phrase.

Typical Windows dispatch mappings:

| Intent | Windows tool |
| --- | --- |
| service status/control | `Get-Service`, `Restart-Service`, `sc.exe` |
| event logs | `Get-WinEvent` |
| package install | `winget install --silent --accept-source-agreements --accept-package-agreements` |
| firewall | `Get-NetFirewallRule`, `New-NetFirewallRule` |
| users/groups | `New-LocalUser`, `Add-LocalGroupMember` |
| GUI screenshot/action | `Screenshot.ps1`, `GuiAction.ps1` |

Every decision and command result is recorded through the audit logger.

## Network model

The chat server binds to loopback (`127.0.0.1:7878`). The installer creates
a `Windows Zombie` Defender Firewall rule group and explicitly denies
chat traffic from non-loopback interfaces. RDP (`3389`) and optional
OpenSSH (`22`) should be restricted to the Tailscale interface or a trusted
management subnet.

Tailscale is optional and uses the normal Windows client:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

## Logging

The agent writes JSONL audit and service logs under
`C:\ProgramData\AiZombie\logs\`. Rotation is implemented by the agent's
built-in size+count logic in `payload/agent/logging.py`; Windows has no
project `built-in size+count log rotation` component and the audit log is not mirrored to Event
Log by default.
