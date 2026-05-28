# Security policy

Windows 11 Zombie deliberately installs a powerful local AI administrator.
Treat every deployment as privileged infrastructure, not a toy chatbot.

## Supported platform

Security guidance applies to Windows 11 22H2+ Pro or Enterprise. Windows
11 Home can run the project, but Group Policy and some firewall profile
features are reduced.

## Trust model

The service runs as `LocalSystem` by default because it is simple and
reliable for Windows Services. The installer also creates a local
Administrators account named `zombie`; operators may switch the service to
that account for closer parity with a dedicated admin identity:

```powershell
sc.exe config Windows11Zombie-Chat obj= .\zombie password= <password>
Restart-Service Windows11Zombie-Chat
```

`LocalSystem` has broad machine privileges and no normal user profile.
The `zombie` account has a clearer identity and ACL target, but still has
administrator rights. In both modes, the **policy engine is the only
privilege gate**. Windows has no Linux-style per-command elevation prompt in this
architecture.

## Policy and audit

`payload/etc/policy.yaml` classifies tools and commands. Read-only
diagnostics may auto-run. Mutating actions require operator approval.
Destructive actions require an explicit confirmation phrase. Any new
privileged behaviour must be routed through `payload/agent/policy.py` and
logged by `payload/agent/audit.py`.

Audit logs are JSONL files under `C:\ProgramData\AiZombie\logs\`. The
agent performs built-in size+count rotation; there is no Event Log mirror
by default and no Windows `built-in size+count log rotation`. Protect and back up these files if
you rely on them for accountability.

## Secrets

Default secrets live in plaintext at:

```text
C:\ProgramData\AiZombie\secrets\env
```

The installer disables inheritance and grants FullControl only to
`BUILTIN\Administrators`, `NT AUTHORITY\SYSTEM`, and `zombie`. Edit the
file with `payload/bin/Secrets-Edit.ps1`; it re-applies ACLs and writes a
SHA-256 audit entry.

DPAPI encryption is a stronger future option and can be adopted by
operators who need host-bound secret protection. The default remains
ACL-protected plaintext for operational transparency and parity with the
legacy `0640` model.

## Network exposure

The chat UI binds to `127.0.0.1:7878`. Windows loopback is local-only, and
the installer also creates Defender Firewall rules in the `Windows11
Zombie` group to deny that port from non-loopback interfaces.

Recommended remote access posture:

- enable RDP only with Network Level Authentication (NLA);
- restrict RDP (`3389`) and optional OpenSSH (`22`) to the Tailscale
  interface or trusted management networks;
- run `& 'C:\Program Files\Tailscale\tailscale.exe' up` from an elevated
  shell and verify the Tailscale Windows service is running;
- never expose the chat port directly to a LAN or the Internet.

## Windows security features

Defender SmartScreen, Microsoft Defender Antivirus, Controlled Folder
Access, and Tamper Protection may block unsigned scripts, downloaded ZIPs,
Python runtimes, or agent subprocesses. Prefer narrowly scoped allow rules
for the repository checkout and `C:\ProgramData\AiZombie\` over disabling
protection globally. Document any allow rule in your local change log.

## Reporting vulnerabilities

Please report suspected vulnerabilities privately through the repository's
security advisory workflow or the maintainer contact listed on GitHub. Do
not open a public issue with exploit details, secrets, or logs containing
private prompts.

Useful reports include:

- the affected version or commit;
- whether the service ran as `LocalSystem` or `zombie`;
- relevant policy snippets;
- sanitized audit entries;
- reproduction steps on Windows 11.

## Coordinated disclosure timeline

We follow a 90-day coordinated disclosure window:

| Day | Action |
| --- | --- |
| 0   | Report received via GitHub Security Advisory (preferred) or `security@japer-technology.example`. Acknowledgement within **3 business days**. |
| 7   | Triage complete; severity & affected versions confirmed. |
| 30  | Fix candidate available; reporter invited to validate. |
| 60  | Pre-disclosure to operators of known production deployments (if any). |
| 90  | Public release + advisory + CVE. |

Critical vulnerabilities (RCE, sandbox escape, secret exfiltration) may be
fast-tracked.

### PGP

A PGP key for `security@japer-technology.example` is published at
[https://github.com/japer-technology/.well-known/security.txt](https://github.com/japer-technology/.well-known/security.txt).
Fingerprint will be listed in `docs/THREAT-MODEL.md` once the org key is
provisioned.

### Safe harbour

Good-faith security research that abides by this policy will not be
pursued under DMCA or CFAA equivalents. Do not access data that is not
your own, do not perform denial-of-service testing against shared
infrastructure, and do not retain copies of data accessed during
research.
