# 0005. Single repo for installer, agent runtime, and bridges

* Status: Accepted
* Date: 2025-01-01

## Context

The project has at least four moving parts:

* PowerShell installer / uninstaller / lifecycle scripts.
* Python agent (HTTP server, policy, audit, tools, history).
* Node bridges for `@earendil-works/pi-coding-agent`.
* Policy and configuration YAML.

These could live in separate repos with versioned releases pulled
in at install time.

## Decision

Keep everything in a single repository. The release artifact is a
zip of the full tree; the installer copies the payload directory
into `C:\ProgramData\AiZombie\`.

## Consequences

* A change that crosses the installer/agent/bridge boundary is one
  PR, not three. The smoke test exercises all components together.
* Version skew across components is impossible by construction —
  see [`../UPGRADE.md`](../UPGRADE.md). We do not test mixed
  versions and explicitly do not support them.
* The release zip is larger than a per-component release. That is
  acceptable for a desktop install.
* The CI matrix is simpler: one Windows runner, one Ubuntu runner
  for non-Windows checks.

## Alternatives considered

* Split installer / agent into separate repos with semver pinning
  — rejected for the boundary-crossing cost.
* Distribute the agent as a Python wheel — rejected because the
  Node bridge is a peer, not a transitive dependency.
* Ship as a single PowerShell module — rejected because the Python
  agent needs a real interpreter and venv lifecycle the module
  system does not model.
