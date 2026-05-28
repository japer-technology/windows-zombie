# 0002. Default to plaintext+ACL secrets; DPAPI is opt-in

* Status: Accepted
* Date: 2025-01-01

## Context

The chat service needs at least one provider API key. The options
for storing it on a Windows host are:

* Plaintext file with NTFS ACLs — operationally transparent,
  trivially editable, parity with the legacy POSIX `0640` model.
* DPAPI (`ProtectedData`) at machine scope — encrypted at rest,
  bound to the host, opaque to copy/move.
* Windows Credential Manager — designed for interactive user
  credentials, awkward to call from a service.
* External KMS (Azure Key Vault, HashiCorp Vault, …) — pulls in a
  network dependency the project explicitly does not want.

## Decision

* Default to plaintext at `C:\ProgramData\AiZombie\secrets\env`
  with explicit ACLs: `FullControl` for Administrators and SYSTEM,
  `Read` for the agent account, inheritance disabled.
* Ship `Secrets-Edit.ps1` to re-apply the ACL on every save and
  write a SHA-256 audit entry.
* Provide an opt-in `secrets.mode = dpapi` (machine scope) for
  operators who need encryption at rest.

## Consequences

* The default is greppable, diff-able, and obvious in
  diagnostics — the right trade-off when the dominant audience is
  individual operators and security researchers.
* An attacker who reaches Administrator can read the secrets in
  either mode; DPAPI does not change that, it only changes the
  cold-storage / disk-image scenario.
* DPAPI mode binds the secrets to the host, so backups need the
  cleartext export captured at backup time. The backup tooling
  must be aware.

## Alternatives considered

* DPAPI by default — rejected as operationally opaque for a
  project where transparency is a feature.
* Vault integration — rejected for the network dependency.
* Credential Manager — rejected for the service-vs-user mismatch.
