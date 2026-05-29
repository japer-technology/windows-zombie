<!-- triggers: winget, package, install, uninstall, upgrade, msi, msstore -->
# Skill: WinGet package management on Windows 10/11

This skill is loaded when the operator's recent prompts mention WinGet,
package installs, MSI/MSStore sources, or related package terms.

Operating rules:

- Prefer the typed `pkg.query` and `pkg.install` tools over `shell.run`
  when answering "is X installed?" or "install X". They are gated by
  the same policy classes but produce cleaner observations and pick
  the right backend per OS (WinGet on Windows, apt on Linux).
- For investigation, `pkg.query` wraps `winget show` and `winget list`.
  Use it before suggesting installs so the operator sees the current
  state.
- For installs, `pkg.install` runs `winget install --silent
  --accept-source-agreements --accept-package-agreements` and is
  classified `system_change`; it always waits for operator approval.
- Never call `winget upgrade --all` unattended unless the operator
  explicitly asked for a full system upgrade. Upgrades can restart
  services and require reboots.
- Do not add or modify WinGet sources (`winget source add`,
  `winget source remove`) without explicit operator consent; a new
  source is a security change.
- If WinGet is unavailable on the host, report it and ask the
  operator how to proceed (likely path: install the "App Installer"
  from the Microsoft Store, or fall back to `choco` if that is what
  the operator already uses). Do not silently fall back to an
  `iwr | iex` pattern — there is no generic `http.get` tool and that
  pattern is forbidden by the threat model.
- IDs are case-sensitive; prefer the exact PackageIdentifier shown by
  `winget search` (e.g. `Microsoft.PowerToys`, not `powertoys`).
