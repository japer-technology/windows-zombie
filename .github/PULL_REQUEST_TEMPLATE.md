<!--
Thanks for contributing. Please fill in the checklist below so reviewers
can move quickly. Delete sections that do not apply.
-->

## Summary

<!-- One or two sentences describing the change and the motivation. -->

## Related issues

<!-- e.g. "Closes #123", "Refs #45". -->

## Changes

<!-- Bulleted list of the meaningful changes. -->

## Checklist

- [ ] The installer remains **idempotent** — re-running `install` converges to the desired state without errors.
- [ ] The installer still supports **non-interactive** mode (`ZOMBIE_NONINTERACTIVE=1`) without prompting.
- [ ] Any new privileged behaviour goes through the **policy gate** (`payload/etc/policy.yaml` + `payload/agent/policy.py`).
- [ ] Any new behaviour worth investigating later is written to the **audit log** (`payload/agent/audit.py`).
- [ ] `payload/etc/policy.yaml` is updated and every new tool has a classification (deny-by-default rule).
- [ ] Docs under `docs/` are updated (operations, recovery, threat model, policy reference as applicable).
- [ ] A smoke or unit test exercises the new code path (`tests/Smoke.ps1`, `tests/python/`, or `tests/Pester/`).
- [ ] No secrets, screenshots, or local state have been committed.
- [ ] `pwsh -File build.ps1 lint` passes locally.
- [ ] `pwsh -File build.ps1 test` passes locally.
- [ ] User-facing changes are noted in `CHANGELOG.md` (Conventional Commits style).

## Risk / rollback

<!--
What is the worst case if this lands and is wrong? How would an
operator recover? (e.g. `pwsh -File scripts/Install.ps1 repair`,
`pwsh -File scripts/Install.ps1 restore -Path ...`, or
`pwsh -File scripts/Uninstall.ps1 -Archive -AssumeYes`).
-->
