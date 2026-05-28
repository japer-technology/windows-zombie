# Governance

`windows11-zombie` is maintained by [japer-technology](https://github.com/japer-technology).
This document captures how decisions are made so contributors know
what to expect.

## Roles

| Role | Who | Powers |
| --- | --- | --- |
| Maintainer | listed in [`MAINTAINERS.md`](MAINTAINERS.md) | Merge PRs, cut releases, manage security advisories, administer the GitHub org. |
| Contributor | anyone with a merged PR | Triage issues, open PRs, comment on RFCs. |
| Security responder | maintainers + listed responders | Receive and triage reports from `SECURITY.md`. |

## Decision making

* **Day-to-day code changes** — lazy consensus on the PR. A single
  maintainer LGTM is sufficient if no blocking review is open within
  72 hours.
* **User-visible behaviour changes** — must update `docs/` and
  `CHANGELOG.md`. Two maintainer LGTMs preferred when one is
  available.
* **Security-relevant changes** — must include a `THREAT-MODEL.md`
  delta or an explicit "no change to threat model" note. Two
  maintainer LGTMs preferred.
* **Architecture changes** — require an [ADR](docs/ADR/) explaining
  the alternatives considered.
* **Disputes** — escalated to the maintainer team. Ties are broken by
  the longest-tenured maintainer.

## Release cadence

* **Patch** (`x.y.Z`) — as needed, no schedule.
* **Minor** (`x.Y.0`) — roughly monthly when there is enough material.
* **Major** (`X.0.0`) — only on breaking changes, with a deprecation
  notice landed at least one minor release earlier.

Releases follow [Semantic Versioning 2.0.0](https://semver.org/) and
[Conventional Commits](https://www.conventionalcommits.org/). The
`VERSION` file is the source of truth.

## Becoming a maintainer

Maintainers are nominated by an existing maintainer after a
contributor has demonstrated:

* sustained contributions over at least three months,
* an understanding of the policy/audit/recovery invariants documented
  in `docs/THREAT-MODEL.md`,
* willingness to be on the security responder rotation.

## Code of Conduct

All participants are bound by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
