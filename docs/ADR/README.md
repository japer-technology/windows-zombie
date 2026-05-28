# Architecture Decision Records

ADRs capture the *why* behind non-trivial design decisions in
`windows11-zombie`. Add a new record when proposing a change that
touches one of the following:

* Service identity, ACL model, or trust boundaries.
* Audit, policy, or approval mechanics.
* The chat HTTP surface.
* Packaging or delivery channels.
* Cross-platform parity story.

## Format

Number sequentially: `0001-title.md`, `0002-title.md`, …. Use the
[MADR](https://adr.github.io/madr/) template below.

```markdown
# NNNN. Short title

* Status: proposed | accepted | superseded by NNNN
* Date: YYYY-MM-DD

## Context

What problem are we solving? Constraints, prior art.

## Decision

What we picked. Imperative voice.

## Consequences

Positive, negative, and risks. Operational impact.

## Alternatives considered

What else we looked at and why it lost.
```

## Index

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-service-identity.md) | Service runs as LocalSystem with a `zombie` account opt-in | Accepted |
| [0002](0002-secrets-acl-vs-dpapi.md) | Default to plaintext+ACL secrets; DPAPI is opt-in | Accepted |
| [0003](0003-jsonl-audit-vs-event-log.md) | JSONL audit log with hash chain, Event Log mirror for criticals | Accepted |
| [0004](0004-policy-gate-vs-uac.md) | Policy gate is the only authority; no UAC interception | Accepted |
| [0005](0005-monorepo-agent-runtime.md) | Single repo for installer, agent runtime, and bridges | Accepted |

## Appendix

The historical [`../ALTERNATIVES.md`](../ALTERNATIVES.md) and the
`ALTERNATIVE-*.md` family in `docs/` pre-date the ADR format and
remain authoritative for the comparisons they cover.
