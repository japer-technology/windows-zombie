# Windows 10 possibilities

> **✅ Implementation status (done).** This analysis has now been acted
> on. The project was renamed from `windows11-zombie` to `windows-zombie`,
> the single OS gate was generalised to `Assert-SupportedWindows` (floor
> Windows 10 1809 / build 17763), the service/task/firewall/PATH-shim
> identifiers were renamed to their version-neutral `WindowsZombie-*`
> forms with an automatic migration step, and the docs, skills, and
> agent system prompt now describe a "Windows 10 or Windows 11" target.
> See [`CHANGELOG.md`](CHANGELOG.md), [`docs/UPGRADE.md`](docs/UPGRADE.md),
> and [`docs/REQUIRES.md`](docs/REQUIRES.md). The remainder of this
> document is retained as the design rationale for that work.

> Could `windows-zombie` be modified to operate on **both Windows 10
> and Windows 11**? Short answer: **yes, with modest, well-contained
> changes.** Nothing in the design depends on a Windows 11-only kernel
> feature. The "11" in the original name was a target and a default, not a
> hard technical requirement. This document maps every Windows-version
> assumption in the repository and rates how much work each one would
> take to make dual-target.

This began as an analysis document. The **Small** and **Medium** tiers
below (the functional OS gate and the doc/prompt sweep) plus the optional
**rename** have since been implemented. See
[`docs/REQUIRES.md`](docs/REQUIRES.md) for the current, authoritative
requirements and [`ROADMAP.md`](ROADMAP.md) for what is planned next.

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

`scripts/Common.ps1` originally defined `Assert-Windows11`, called from
`scripts/Install.ps1`. It used to:

- throw if the OS caption did not contain `Windows`; and
- only **warn** (not block) when the build was `< 22000`.

So the installer already *ran* on Windows 10 — it just printed a
"supported target" warning. To make Windows 10 a first-class target the
implemented change was to:

1. Rename/generalise the check to `Assert-SupportedWindows` and set a
   real floor that includes Windows 10 (build `>= 17763`, i.e. 1809, the
   first release with modern WinGet/App Installer and stable
   `New-NetFirewallRule` behaviour).
2. Keep a soft warning for builds below the tested floor rather than a
   hard throw, preserving the lenient posture.

This was a small, localised change with test coverage extended under
`tests/Pester/Common.Tests.ps1`.

## Version-specific assumptions inventory

These were the concrete places that mentioned or assumed Windows 11.
Most were cosmetic; all have now been addressed.

- **Functional**
  - `scripts/Common.ps1` — the build-floor gate (now
    `Assert-SupportedWindows`, with `Assert-Windows11` kept as an alias).
- **Detection (now build-accurate)**
  - `payload/agent/server.py` — `machine_facts()` labels Windows 10 vs 11
    from the build number (>= 22000 is Windows 11) for the system prompt.
- **Docs and prompts**
  - `README.md`, `docs/REQUIRES.md`, `docs/FAQ.md`,
    `docs/QUICKSTART.md`, and the skills under
    `payload/agent/skills/` now say "Windows 10 or Windows 11".
  - `payload/agent/templates/APPEND_SYSTEM.md.tmpl` and the inline
    `APPEND_SYSTEM_TEMPLATE` in `server.py` now tell the model it
    administers "a Microsoft Windows 10 or Windows 11 machine".
- **Branding and packaging (renamed)**
  - Repo name, service names (`WindowsZombie-Chat`,
    `WindowsZombie-Health`), the `windows-zombie.cmd` shim, event-log
    source `WindowsZombie-Chat`, firewall group, and the manifests
    under `packaging/` all carry "11" in identifiers.

## What changed, by effort (all completed)

### Small — make it *work* on Windows 10 ✅

- Generalised `Assert-Windows11` into `Assert-SupportedWindows`, a
  supported-range check with a sensible floor (1809 / 17763) and soft
  warnings.
- Extended `tests/Pester/Common.Tests.ps1` to cover the gate, the alias,
  and the build floor.
- Added a "Windows 10" note to `docs/REQUIRES.md` and `docs/FAQ.md`.

With this the product is functional on Windows 10; the rest is polish.

### Medium — make it *feel* dual-target ✅

- Swept the docs and the system-prompt templates to say
  "Windows 10 or Windows 11" instead of "Windows 11", including the skills.
- The Windows Sandbox recipe note
  ([`examples/sandbox/`](examples/sandbox/)) calls out Win10 Pro 1903+;
  the `.wsb` itself is unchanged.
- WinGet wording: App Installer ships on Win10 1809+ but older images may
  need a Microsoft Store update; the existing choco fallback in
  `Common.ps1` already covers hosts without WinGet.

### Larger — rename for a neutral identity ✅

The *brand* no longer implies "11". Because identifiers are externally
visible, the rename was paired with an automatic migration:

- Service names, event-log source, the PATH shim, firewall group, and
  packaging IDs moved to their `WindowsZombie-*` / `windows-zombie` forms.
  `Remove-LegacyServiceArtifact` migrates existing installs (see
  [`docs/UPGRADE.md`](docs/UPGRADE.md)) so none are orphaned.
- The repository name itself (`windows-zombie`) and all docs/badges were
  updated.
- This was purely a naming decision; it adds no Windows 10 capability but
  gives the dual-target product a coherent identity.

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
