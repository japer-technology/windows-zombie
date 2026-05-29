# Roadmap

The roadmap is intentionally short. Anything not listed here is
either a bug-fix backlog item or a future RFC.

Track the per-release scope on the [GitHub Projects board](https://github.com/orgs/japer-technology/projects)
and the per-item history in [`CHANGELOG.md`](CHANGELOG.md).

## Now (`0.4.x`)

* Solidify the recovery story (`backup`/`restore` subcommands,
  scheduled backup task, `Verify-Audit.ps1`).
* Harden audit integrity (hash-chained JSONL).
* Documentation completeness — every operational and security topic
  is covered by a doc, not by source-code spelunking.

## Next (`0.5.x`)

* Signed releases (Authenticode + Sigstore) and SBOM emission on tag.
* WinGet, Chocolatey, and MSI delivery channels.
* DPAPI-encrypted secrets as an opt-in mode.
* Optional Prometheus `/metrics` endpoint on the loopback port.

## Later (`0.6.x` and beyond)

* End-to-end VM test in CI (Windows 10/11 sandbox or Azure VM).
* OpenTelemetry exporter for fleet operators.
* Group Policy / Intune deployment guide with worked examples.
* Optional remote-attestation / TPM-bound audit anchors.

## Out of scope

* Multi-user chat or hosted/shared modes — Windows Zombie is and
  remains a single-machine local admin.
* Cross-platform parity with the Linux variants is not a goal; the
  `docs/ALTERNATIVE-*.md` documents capture that history.

## Asking for changes

Open an issue or start a [discussion](https://github.com/japer-technology/windows-zombie/discussions)
before sending a roadmap-changing PR. ADRs live under
[`docs/ADR/`](docs/ADR/).
