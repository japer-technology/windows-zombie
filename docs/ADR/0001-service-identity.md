# 0001. Service runs as LocalSystem with a `zombie` account opt-in

* Status: Accepted
* Date: 2025-01-01

## Context

The chat service has to run unattended at boot, restart on failure,
have full Administrator rights, and bind a local TCP port. The
candidates were:

* `LocalSystem` — the standard Windows Service identity. Maximum
  privilege, no profile, no password to manage.
* A dedicated local Administrator account (`zombie`) — cleaner ACL
  target, identifiable in audit, requires password management.
* The interactive operator's account — would require the operator
  to be logged in, defeating the "service" model.

## Decision

* Default: register the service as `LocalSystem`.
* Always create a local Administrators account named `zombie`
  (overridable via `ZOMBIE_USER`) during install.
* Document the `sc.exe config Windows11Zombie-Chat obj= .\zombie`
  one-liner so operators who want a dedicated identity can opt in
  without re-running the installer.

## Consequences

* Install is simple and reliable: no interactive password prompt
  when only `LocalSystem` is needed.
* The `zombie` account exists either way, so ACLs on `secrets\` and
  `state\` can grant it `Read` / `Modify` without conditional
  logic.
* `LocalSystem` is broad. The policy gate, not the service identity,
  is the safety boundary. This is called out in
  [`THREAT-MODEL.md`](../THREAT-MODEL.md).
* Operators in regulated environments will typically prefer the
  `zombie` identity for accountability.

## Alternatives considered

* `NT SERVICE\Windows11Zombie-Chat` virtual account — gives unique
  identity but cannot be added to local Administrators, so the
  service could not perform the WinGet/firewall/service operations
  the agent needs.
* A managed service account (MSA/gMSA) — requires Active Directory,
  which we cannot assume.
