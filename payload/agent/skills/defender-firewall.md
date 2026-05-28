<!-- triggers: firewall, defender, netsh, port, ingress, egress, NetFirewallRule, advfirewall -->
# Skill: Windows Defender Firewall

This skill is loaded when the operator mentions the firewall,
Defender Firewall, `netsh advfirewall`, or port-level network policy.

Operating rules:

- `Get-NetFirewallProfile` and `Get-NetFirewallRule` (via `net.status`
  or `shell.run`) are `read_only` and run automatically. Use them
  before suggesting any rule change.
- `New-NetFirewallRule`, `Set-NetFirewallRule`, `Remove-NetFirewallRule`,
  `Enable-NetFirewallRule`, and `Disable-NetFirewallRule` are
  `network_change`. Every one waits for explicit operator approval.
  Disabling a profile entirely (`Set-NetFirewallProfile -Enabled False`)
  is destructive and requires the confirmation phrase.
- Never disable Defender Firewall as part of a routine diagnosis. If
  a service appears unreachable, narrow the rule rather than open the
  firewall.
- The Windows 11 Zombie default policy expects:
    * RDP (TCP/3389) to remain reachable from the Tailscale interface;
    * SSH (TCP/22) — if `Set-Service sshd` was enabled — to remain
      reachable from the Tailscale interface;
    * the chat service (TCP/7878) to stay blocked on every
      non-loopback interface.
  Do not propose rules that would weaken any of these without
  explicit operator consent.
- When suggesting a rule, render it as a single PowerShell command
  (e.g. `New-NetFirewallRule -DisplayName "..." -Direction Inbound
  -Action Allow -Protocol TCP -LocalPort 3389
  -RemoteAddress 100.64.0.0/10`) so the operator can audit the exact
  effect before approving.
- Profiles (Domain / Private / Public) matter. Always state which
  profile your rule targets — a "Public profile" rule does nothing if
  the active interface is classified Private.
