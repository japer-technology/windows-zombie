# Frequently asked questions

## What is it?

A local, policy-gated AI Systems Administrator for Windows 11. It
runs as a loopback-only HTTP chat service on `127.0.0.1:7878`,
mediated by a closed tool registry and an editable
[policy file](POLICY.md). See [`VISION.md`](VISION.md) for the
"why" in one paragraph.

## Is it safe to run on my workstation?

No. Treat every install as privileged infrastructure. Use Windows
Sandbox, a disposable Hyper-V VM, or a throwaway test machine. See
[`THREAT-MODEL.md`](THREAT-MODEL.md) for the abuse cases we
considered.

## Does it phone home?

No. The chat service binds to loopback only, and the installer
refuses to bind elsewhere. The only outbound traffic is whatever
provider you put in `secrets\env` (for example OpenAI or Anthropic).
WinGet installs are made by `Install.ps1` on first run only.

## Where does it store state?

`C:\ProgramData\AiZombie\` by default; override with
`AI_ZOMBIE_ROOT`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the
full tree.

## Can I run the agent without the chat UI?

Yes — call `python payload/agent/server.py --render-append-system`
for prompt rendering, or import `payload/agent/pi_mono.py` from your
own driver. The HTTP server is just one front-end.

## How do I rotate provider keys?

Use `payload/bin/Secrets-Edit.ps1` — it reapplies the ACL and writes
a SHA-256 audit entry. Restart the service afterwards:

```powershell
pwsh -File payload/bin/Secrets-Edit.ps1
Restart-Service Windows11Zombie-Chat
```

## Does it support Windows 11 Home?

Best-effort. Group Policy and some firewall profile features are
unavailable on Home. The service and policy gate still work. CI runs
on `windows-latest` (Pro).

## Why not run inside a container?

Windows Sandbox is the closest thing and is documented under
[`examples/sandbox/`](../examples/sandbox/). Windows containers
don't currently expose the GUI/firewall/service surface we exercise.

## How do I uninstall?

```powershell
pwsh -File scripts/Uninstall.ps1 -Archive -AssumeYes
```

The `-Archive` switch dumps state and secrets under
`C:\ProgramData\AiZombie-backups\` first. See [`RECOVERY.md`](RECOVERY.md)
for restore.

## How do I cite it?

See [`CITATION.cff`](../CITATION.cff).
