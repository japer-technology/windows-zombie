# 0004. Policy gate is the only authority; no UAC interception

* Status: Accepted
* Date: 2025-01-01

## Context

On Linux the analogous project relied on `sudo` rules to gate
privileged actions. On Windows the equivalent would be UAC, but UAC
is interactive, depends on a logged-in user with consent.exe in the
foreground, and cannot be brokered from a Windows Service. We need
a gating mechanism that works headlessly.

## Decision

* The service runs with full Administrator rights from boot. Every
  command the agent proposes is classified by `policy.py` against
  `policy.yaml`. The classification determines whether the
  command auto-runs (`read_only`), waits for operator approval
  (`user_change`, `system_change`, `network_change`), or also
  requires a confirmation phrase (`destructive`).
* `default_class` is `destructive`, so unknown commands fail-closed
  rather than open.
* `classify_tool` re-runs `classify` against the argv when the tool
  is `shell.run`, so the model cannot launder a privileged command
  through a generic shell.
* The approval queue is surfaced in the chat UI and persisted to
  the SQLite events table; nothing executes silently.

## Consequences

* The mechanism works headlessly: a Scheduled Task, an RDP
  session, or a Tailscale-tunnelled browser all interact with the
  same approval queue.
* There is no second authority. An attacker who edits
  `policy.yaml` weakens the gate; the ACL on the file is the
  only mitigation. This is documented in
  [`THREAT-MODEL.md`](../THREAT-MODEL.md).
* The classifier is the safety-critical component. Tests around
  it must exceed `≥80%` coverage and a CI guard requires every
  new tool in the registry to have a classification.

## Alternatives considered

* Bouncing every elevated command through UAC — incompatible with
  a Windows Service and with unattended fleet operation.
* Running the service unprivileged and elevating per command — no
  Windows-native mechanism to do this reliably from a service.
* Using AppLocker / WDAC as the gate — orthogonal: they restrict
  *what* can run, not *who is asking for it to run* or *whether
  the operator agreed*.
