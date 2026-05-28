"""Command execution with timeout, stdout/err/exit capture, and a hook
for proposing follow-up verification checks.

On Windows the command string is handed to ``cmd.exe /d /s /c`` (no
profile, no auto-extensions, no command-line preprocessing) so simple
chains like ``a && b`` and redirections behave the way the agent's
prompts assume. PowerShell-specific commands embed an explicit
``powershell.exe -NoProfile -Command "..."`` inside the string —
``cmd.exe`` is the *shell*, ``powershell.exe`` is the *interpreter*.

On POSIX hosts the command is handed to ``bash -c`` (not ``-lc``;
sourcing the login profile leaks MOTD and slows every call by 50–200
ms, see FIX-3-16).
"""
from __future__ import annotations

import os
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass

DEFAULT_TIMEOUT = int(os.environ.get("ZOMBIE_COMMAND_TIMEOUT", "300"))

_IS_WINDOWS = sys.platform.startswith("win")


@dataclass
class CommandResult:
    command: str
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: int
    follow_up: list[str]


def _propose_follow_ups(command: str, exit_code: int) -> list[str]:
    """Suggest small read-only checks the assistant can run to verify
    the result of ``command``."""
    follow_ups: list[str] = []
    head = command.split(None, 1)[0] if command.strip() else ""
    try:
        # FIX-3-05: shlex.split raises ValueError on unbalanced quotes
        # (e.g. ``apt install "foo``). _propose_follow_ups must never
        # raise — fall back to a naive whitespace split so the audit
        # event still records something useful.
        tokens = shlex.split(command, posix=not _IS_WINDOWS) if command.strip() else []
    except ValueError:
        tokens = command.split() if command.strip() else []

    head_lc = head.lower().rstrip(".exe")

    if _IS_WINDOWS:
        if head_lc == "winget" and len(tokens) > 1 and tokens[1].lower() in {"install", "uninstall", "upgrade"}:
            for arg in tokens[2:]:
                if arg.startswith("-") or arg.startswith("/") or "=" in arg:
                    continue
                follow_ups.append(f"winget list --id {shlex.quote(arg)} --disable-interactivity")
        elif head_lc in {"start-service", "stop-service", "restart-service",
                         "set-service", "sc"} and len(tokens) > 1:
            unit = tokens[-1]
            follow_ups.append(
                f'powershell.exe -NoProfile -Command "Get-Service -Name {shlex.quote(unit)}"'
            )
        elif head_lc == "new-netfirewallrule" or "netfirewallrule" in head_lc:
            follow_ups.append(
                'powershell.exe -NoProfile -Command "Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction"'
            )
        elif "tailscale" in head_lc:
            follow_ups.append('"C:\\Program Files\\Tailscale\\tailscale.exe" status')
        if exit_code != 0 and "get-winevent" not in command.lower():
            follow_ups.append(
                'powershell.exe -NoProfile -Command '
                '"Get-WinEvent -LogName Application -MaxEvents 50 | Format-Table TimeCreated,LevelDisplayName,Message -Wrap"'
            )
        return follow_ups

    if head in {"apt", "apt-get"} and len(tokens) > 1 and tokens[1] in {"install", "remove", "purge"}:
        for pkg in tokens[2:]:
            if pkg.startswith("-"):
                continue
            follow_ups.append(f"dpkg -s {shlex.quote(pkg)} | head -n 5")
    elif head == "systemctl" and len(tokens) > 2 and tokens[1] in {
        "start", "stop", "restart", "reload", "enable", "disable", "mask", "unmask"
    }:
        unit = tokens[2]
        follow_ups.append(f"systemctl is-active {shlex.quote(unit)}")
        follow_ups.append(f"systemctl status --no-pager {shlex.quote(unit)} | head -n 20")
    elif head == "ufw":
        follow_ups.append("ufw status verbose")
    elif head == "tailscale":
        follow_ups.append("tailscale status")
    elif head == "docker" and len(tokens) > 1 and tokens[1] in {"run", "start", "restart"}:
        follow_ups.append("docker ps")

    if exit_code != 0 and "journalctl" not in command:
        follow_ups.append("journalctl -n 50 --no-pager")
    return follow_ups


def run(command: str, *, timeout: int = DEFAULT_TIMEOUT, cwd: str | None = None,
        env: dict[str, str] | None = None) -> CommandResult:
    """Run ``command`` through the platform shell so common shell
    features (pipelines, redirections, ``&&``) work.

    The chat service is itself running as the local agent account
    (``zombie`` by default; configurable at install time); commands
    inherit that identity. Privileged Linux invocations must include
    ``sudo``; on Windows the agent account itself is an Administrator
    (or the service runs as LocalSystem), and the policy gate in
    ``policy.py`` is the only authority that approves a mutating
    command before this function is called.
    """
    if _IS_WINDOWS:
        # ``cmd.exe /d`` skips AutoRun, ``/s`` simplifies quoting, ``/c``
        # runs the string and exits.
        argv = [os.environ.get("ComSpec", "cmd.exe"), "/d", "/s", "/c", command]
    else:
        # FIX-3-16: use ``-c`` not ``-lc``. A login shell sources
        # /etc/profile, profile.d/*, and ~/.bash_profile for every
        # command — adds 50-200 ms, can change PATH unexpectedly,
        # and leaks MOTD lines into stderr (and thus the
        # assistant's context). The environment is already
        # constructed explicitly below.
        argv = ["bash", "-c", command]

    start = time.monotonic()
    try:
        completed = subprocess.run(  # noqa: S603 - the policy gate vetted this
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env={**os.environ, **(env or {})},
            check=False,
        )
        stdout = completed.stdout
        stderr = completed.stderr
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = (exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes)
                  else (exc.stderr or "")) + f"\n[timeout after {timeout}s]"
        exit_code = 124
    duration_ms = int((time.monotonic() - start) * 1000)
    return CommandResult(
        command=command,
        exit_code=exit_code,
        stdout=stdout[-16_000:],   # cap to keep audit/UI sane
        stderr=stderr[-16_000:],
        duration_ms=duration_ms,
        follow_up=_propose_follow_ups(command, exit_code),
    )
