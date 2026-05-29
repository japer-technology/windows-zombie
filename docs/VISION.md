# Vision

windows-zombie turns a Windows 10 or Windows 11 PC into a local, accountable AI Systems
Administrator. The operator keeps control through policy, approval, audit,
and a desktop session they can inspect.

## What we are building

A private assistant that can:

- diagnose a Windows desktop or workstation;
- explain proposed fixes before making them;
- use WinGet, Windows Services, Defender Firewall, local users/groups,
  logs, and GUI automation through documented tools;
- keep a durable audit trail under `C:\ProgramData\AiZombie\logs\`;
- work over RDP and/or Tailscale without exposing the chat UI directly.

## What we are not building

- a stealth remote administration tool;
- a malware-like persistence mechanism;
- a cloud control plane for fleets;
- a bypass for Windows security controls;
- an agent that mutates the system without policy and operator approval.

## Design stance

The agent may be powerful, but it should be boringly observable. A Windows
operator should be able to read the policy, inspect the service, review the
logs, and uninstall the system without reverse engineering hidden state.
