# Windows 10 possibilities

> Could `windows11-zombie` be modified to operate on **both Windows 10
> and Windows 11**? Short answer: **yes, with modest, well-contained
> changes.** Nothing in the design depends on a Windows 11-only kernel
> feature. The "11" in the name is a target and a default, not a hard
> technical requirement. This document maps every Windows-version
> assumption in the repository and rates how much work each one would
> take to make dual-target.

This is an analysis document, not a commitment. It does not change any
behaviour. See [`docs/REQUIRES.md`](docs/REQUIRES.md) for the current,
authoritative requirements and [`ROADMAP.md`](ROADMAP.md) for what is
actually planned.

## TL;DR feasibility

| Area | Win10 viable today? | Work to dual-target |
| --- | --- | --- |
| Python/Node agent runtime | Yes | None |
| Chat HTTP service (loopback) | Yes | None |
| Policy engine + audit log | Yes | None |
| Windows Service supervision (`sc.exe`) | Yes | None |
| Scheduled Task (`Health-Check.ps1`) | Yes | None |
| Defender Firewall (`New-NetFirewallRule`) | Yes | None |
| ACLs (`icacls` / .NET ACL APIs) | Yes | None |
| PowerShell 7 / 5.1 | Yes | None |
| WinGet / App Installer | Yes (Win10 1809+) | Docs only |
| OS gate (`Assert-Windows11`) | Blocks intent, not capability | **Small** |
| Branding, docs, manifests | n/a | **Medium (cosmetic, broad)** |
| GUI automation (SendInput/screenshot) | Yes | None |
| Windows Sandbox trial recipe | Yes (Win10 Pro 1903+) | Docs only |

The only *functional* gate is one helper function. Everything else is
naming, documentation, and packaging metadata.

## How the project is layered

Understanding the layers makes the feasibility obvious. The runtime is
deliberately split (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)):

- **Cross-platform agent core** — `payload/agent/*.py` (Python 3.12) plus
  a Node bridge. This code already resolves paths and shells through
  `sys.platform` branches (`payload/agent/paths.py`,
  `payload/agent/runner.py`) and was explicitly written for parity with
  the upstream `ubuntu-zombie` project. It has **no** Windows 11
  dependency.
- **Windows integration layer** — `scripts/*.ps1` and
  `payload/bin/*.ps1`. These call standard Windows surfaces: `sc.exe`,
  Scheduled Tasks, `New-NetFirewallRule`, ACL cmdlets, and WinGet. Every
  one of these APIs shipped in Windows 10.
- **Policy + skills** — `payload/etc/policy.yaml` and
  `payload/agent/skills/*.md`. Pure configuration and prose; OS-version
  agnostic.

Because the privileged surfaces are all Windows 10-era APIs, "support
Windows 10" is mostly about *removing an artificial assumption*, not
*adding new capability*.

## The one real gate

`scripts/Common.ps1` defines `Assert-Windows11`, called from
`scripts/Install.ps1`. Today it:

- throws if the OS caption does not contain `Windows`; and
- only **warns** (does not block) when the build is `< 22000`.

So the installer already *runs* on Windows 10 — it just prints a
"supported target" warning. To make Windows 10 a first-class target you
would:

1. Rename/generalise the check (e.g. `Assert-SupportedWindows`) and set a
   real floor that includes Windows 10 (build `>= 17763`, i.e. 1809, the
   first release with modern WinGet/App Installer and stable
   `New-NetFirewallRule` behaviour).
2. Keep a soft warning for builds below the tested floor rather than a
   hard throw, preserving today's lenient posture.

This is a small, localised change with existing test coverage under
`tests/` to extend.

## Version-specific assumptions inventory

These are the concrete places that mention or assume Windows 11. Most are
cosmetic.

- **Functional**
  - `scripts/Common.ps1` — `Assert-Windows11` build floor (the one gate
    above).
- **Detection (already dual-aware)**
  - `payload/agent/server.py` — `machine_facts()` *already* labels
    Windows 10 vs 11 from the build number for the system prompt. No
    change needed; it is evidence the codebase anticipated this.
- **Docs and prompts (cosmetic)**
  - `README.md`, `docs/REQUIRES.md`, `docs/FAQ.md`,
    `docs/QUICKSTART.md`, and the skills under
    `payload/agent/skills/` say "Windows 11".
  - `payload/agent/templates/APPEND_SYSTEM.md.tmpl` and the inline
    `APPEND_SYSTEM_TEMPLATE` in `server.py` tell the model it administers
    "a Microsoft Windows 11 machine".
- **Branding and packaging (cosmetic but wide-reaching)**
  - Repo name, service names (`Windows11Zombie-Chat`,
    `Windows11Zombie-Health`), the `windows11-zombie.cmd` shim, event-log
    source `Windows11Zombie-Chat`, firewall group, and the manifests
    under `packaging/` all carry "11" in identifiers.

## What would actually change, by effort

### Small — make it *work* on Windows 10

- Generalise `Assert-Windows11` to a supported-range check with a
  sensible floor (1809) and keep warnings soft.
- Extend the relevant tests in `tests/` to cover a Windows 10 build
  number.
- Add a short "Windows 10" note to `docs/REQUIRES.md` and `docs/FAQ.md`.

With just this, the product is functional on Windows 10 today; the rest
is polish.

### Medium — make it *feel* dual-target

- Sweep the docs and the system-prompt templates to say "Windows 10/11"
  (or "modern Windows") instead of "Windows 11", including the skills.
- Verify the Windows Sandbox recipe note
  ([`examples/sandbox/`](examples/sandbox/)) — Sandbox needs Win10 Pro
  1903+; the `.wsb` itself is unchanged.
- Confirm WinGet wording: App Installer ships on Win10 1809+ but older
  images may need a Microsoft Store update; the existing choco fallback
  in `Common.ps1` already covers hosts without WinGet.

### Larger — rename for a neutral identity (optional)

Only needed if the *brand* should stop implying "11". This is the most
invasive option because identifiers are externally visible:

- Service names, event-log source, the PATH shim, firewall group, and
  packaging IDs would change, which affects upgrade/migration paths
  (`docs/UPGRADE.md`) and any deployed fleet.
- The repository name itself is referenced throughout docs and badges.
- This is purely a naming decision; it adds no Windows 10 capability and
  can be deferred or skipped. Renaming a shipped service requires a
  migration step so existing installs are not orphaned.

## Risks and caveats

- **Edition differences, not version differences, dominate.** As
  [`docs/FAQ.md`](docs/FAQ.md) already notes for Windows 11 Home, Group
  Policy and some firewall-profile controls are reduced on Home editions.
  The same caveat applies to Windows 10 Home and is independent of the
  10-vs-11 question.
- **Test surface.** CI runs on `windows-latest` (currently a Windows 11
  image). True Windows 10 support implies adding a Windows 10 runner or
  documenting it as best-effort, since GitHub-hosted Windows 10 runners
  are limited/being retired.
- **End-of-life.** Windows 10 reaches end of mainstream support in
  October 2025. Investing in Win10 support buys a shrinking window;
  weigh that against the small effort it actually takes.
- **No new attack surface.** None of the changes above add network
  exposure or new privileged tools, so the
  [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) posture is unchanged.

## Recommendation

If the goal is "run on Windows 10 and 11 from one codebase," the
pragmatic path is the **Small** tier: relax the single OS gate, extend
the tests, and adjust a few doc lines. The agent core, service model,
firewall rules, scheduled task, ACLs, and package management already work
on Windows 10. The **Medium** doc/prompt sweep makes the experience
coherent. A full **rename** is an independent branding decision with real
migration cost and **no** functional payoff for Windows 10, so it should
be treated separately.
