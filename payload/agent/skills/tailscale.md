<!-- triggers: tailscale, tailnet, magicdns, tailscaled -->
# Skill: Tailscale (tailnet membership and status) on Windows 10/11

This skill is loaded when the operator mentions Tailscale, the tailnet,
or related networking terms.

Operating rules:

- The Windows CLI lives at `C:\Program Files\Tailscale\tailscale.exe`.
  Always quote the path or call it through `& 'C:\Program Files\Tailscale\tailscale.exe'`.
- `net.status` aggregates `Get-NetIPAddress`, the Defender Firewall
  profile summary, and `tailscale status`; prefer it over raw
  `shell.run` for read-only diagnostics.
- `tailscale up` / `tailscale logout` mutate the network identity of
  the host and are `network_change`. Always wait for operator
  approval, and never include an auth key in the rendered argv — the
  operator should pass it via the secrets file or interactive login,
  not the chat.
- Avoid `tailscale set --ssh=true` unless the operator explicitly
  asked. The Windows Zombie default keeps Tailscale SSH off in
  favour of the host's RDP (and optional `sshd`) so audit log and
  key handling stay consistent.
- If `tailscale status` reports "Logged out", surface that fact and
  ask the operator how to re-enrol; do not attempt re-auth silently.
- Treat the Tailscale IP and MagicDNS name as identifiers, not
  secrets. Auth keys, OAuth client secrets, and preauth keys are
  secrets and must never be echoed.
- The Tailscale service on Windows is `Tailscale`; inspect it with
  `Get-Service Tailscale`, restart it via `Restart-Service Tailscale`
  (which is `network_change`).
