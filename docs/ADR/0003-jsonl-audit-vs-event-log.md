# 0003. JSONL audit log with hash chain, Event Log mirror for criticals

* Status: Accepted
* Date: 2025-01-01

## Context

We need a structured, forensically useful record of every prompt,
tool call, approval, exit code, and verification result. Candidates:

* JSONL file under `logs\` — append-only, grep/jq-friendly,
  rotation managed in-process.
* Windows Event Log — durable, ACL'd, mirrored by enterprise
  collectors, but XML schema is awkward and per-entry size is
  capped.
* SQLite — queryable, but locks complicate concurrent writes from
  the bridge processes.

## Decision

* Primary audit log: JSONL at
  `C:\ProgramData\AiZombie\logs\audit.log`, one event per line,
  with redaction of token-shaped values and sensitive env-var
  assignments before write.
* Each line includes `prev_sha256`, the SHA-256 of the previous
  line, so tampering is detectable. The chain starts with the
  zero hash on a fresh file.
* `Verify-Audit.ps1` validates the chain and exits non-zero on
  mismatch.
* Critical events (`service_start`, `service_stop`,
  `policy_reload`, destructive tool calls, approval denies) are
  *also* mirrored to the Windows Event Log under the
  `Windows11Zombie-Chat` provider so they survive deletion of the
  `logs\` directory.
* In-process size+count rotation: the agent rotates when the file
  exceeds a configurable threshold and keeps a fixed count of
  rotations.

## Consequences

* The JSONL stream is human-readable and machine-readable in the
  same file. No separate parser is required.
* The hash chain detects tampering without preventing it; a kernel
  rootkit can still rewrite the file. This limitation is called
  out in [`THREAT-MODEL.md`](../THREAT-MODEL.md).
* The Event Log mirror is best-effort: if the provider is
  unregistered, mirroring is skipped and the JSONL line still goes
  through.

## Alternatives considered

* Event Log as primary — rejected for tooling friction
  (everything has to go through `Get-WinEvent`).
* SQLite as primary — rejected for concurrent-write fragility
  across the chat service and bridge.
* Signing each line with a per-host key — overkill; the hash chain
  catches tampering with the same forensic value at a fraction of
  the complexity.
