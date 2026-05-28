# Documentation index

`windows11-zombie` ships a deliberately small but complete documentation
tree. The right starting point depends on what you're trying to do.

## I want to try it

1. [`QUICKSTART.md`](QUICKSTART.md) — install, verify, open the chat UI.
2. [`CONFIGURATION.md`](CONFIGURATION.md) — pick a provider, set
   environment variables, edit `policy.yaml`.
3. [`../examples/sandbox/`](../examples/sandbox/) — Windows Sandbox
   `.wsb` recipe for a one-click throwaway trial.

## I'm operating it on real machines

1. [`OPERATIONS.md`](OPERATIONS.md) — day-two runbook: restart, drain,
   rotate secrets, swap providers, switch service identity.
2. [`UPGRADE.md`](UPGRADE.md) — in-place upgrade flow and rollback.
3. [`RECOVERY.md`](RECOVERY.md) — disaster scenarios and copy-paste
   fixes.
4. [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — common errors and
   their resolutions.
5. [`POLICY.md`](POLICY.md) — full reference for every key in
   `payload/etc/policy.yaml`.

## I'm reviewing it for security

1. [`THREAT-MODEL.md`](THREAT-MODEL.md) — STRIDE table, trust
   boundaries, abuse cases, non-goals.
2. [`../SECURITY.md`](../SECURITY.md) — disclosure policy, supported
   versions, default secrets posture.
3. [`API.md`](API.md) — chat HTTP surface, auth assumptions, request
   size limits.
4. [`ARCHITECTURE.md`](ARCHITECTURE.md) — component overview and
   installed layout.

## I'm contributing

1. [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — branch flow, lint,
   tests, commit style.
2. [`../GOVERNANCE.md`](../GOVERNANCE.md) — who decides what.
3. [`ADR/`](ADR/) — Architecture Decision Records for the big calls
   already made. Add a new one when you propose a non-trivial design
   change.
4. [`ALTERNATIVES.md`](ALTERNATIVES.md) and the
   [`ALTERNATIVES-LESSONS.md`](ALTERNATIVES-LESSONS.md) family for
   the history of other approaches we considered.

## I'm deploying it across a fleet

1. [`DEPLOY-INTUNE.md`](DEPLOY-INTUNE.md) — Win32 packaging, detection
   rules, uninstall command.
2. [`../examples/ansible/`](../examples/ansible/) and
   [`../examples/dsc/`](../examples/dsc/) — fleet-rollout recipes.
3. [`../packaging/`](../packaging/) — WinGet, Chocolatey, and MSI
   sources.

## I just want help

[`SUPPORT.md`](SUPPORT.md) — bugs vs questions vs security vs
discussions, with the right link for each.
