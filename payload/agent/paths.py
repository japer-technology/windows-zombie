"""Cross-platform path resolution for Windows 11 Zombie.

All persistent paths used by the agent (install root, state directory,
audit log, secrets file, policy file, skill directories, history
database) are resolved through this module so a single
``AI_ZOMBIE_ROOT`` environment variable relocates the whole tree.

Defaults are Windows-native (``C:\\ProgramData\\AiZombie`` and
``C:\\ProgramData\\AiZombie\\logs``). On non-Windows hosts (developer
machines running unit tests under Linux/macOS) the defaults fall back
to the legacy Ubuntu layout so existing tests keep working without an
explicit environment override.

Every public path constant honours its individual ``ZOMBIE_*`` env
override first, then ``AI_ZOMBIE_ROOT``, then the platform default.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

_IS_WINDOWS = sys.platform.startswith("win")


def _env_path(name: str) -> Path | None:
    value = os.environ.get(name)
    if not value:
        return None
    return Path(value)


def install_root() -> Path:
    """Top-level install directory (mirrors ``/opt/ai-zombie``).

    Honours ``AI_ZOMBIE_ROOT`` (Windows-idiomatic) and the legacy
    ``ZOMBIE_DIR`` (preserved for parity with older bash callers).
    """
    p = _env_path("AI_ZOMBIE_ROOT") or _env_path("ZOMBIE_DIR")
    if p:
        return p
    if _IS_WINDOWS:
        program_data = os.environ.get("ProgramData", r"C:\ProgramData")
        return Path(program_data) / "AiZombie"
    return Path("/opt/ai-zombie")


def config_root() -> Path:
    """Operator-editable configuration root (mirrors ``/etc/ubuntu-zombie``).

    On Windows we co-locate config under the install root so the
    installer only has to ACL one tree; on Linux we keep the
    ``/etc/ubuntu-zombie`` layout for backward compatibility.
    """
    p = _env_path("AI_ZOMBIE_CONFIG")
    if p:
        return p
    if _IS_WINDOWS:
        return install_root() / "etc"
    return Path("/etc/ubuntu-zombie")


def log_root() -> Path:
    """Audit + service log root (mirrors ``/var/log/ubuntu-zombie``)."""
    p = _env_path("AI_ZOMBIE_LOG_ROOT")
    if p:
        return p
    if _IS_WINDOWS:
        return install_root() / "logs"
    return Path("/var/log/ubuntu-zombie")


def state_root() -> Path:
    """Mutable runtime state (history DB, pi-mono per-turn logs, etc.)."""
    p = _env_path("AI_ZOMBIE_STATE")
    if p:
        return p
    return install_root() / "state"


def secrets_path() -> Path:
    """Provider keys + tuning env file."""
    p = _env_path("ZOMBIE_SECRETS")
    if p:
        return p
    return install_root() / "secrets" / "env"


def audit_log_path() -> Path:
    p = _env_path("ZOMBIE_AUDIT_LOG")
    if p:
        return p
    return log_root() / "audit.log"


def policy_path() -> Path:
    p = _env_path("ZOMBIE_POLICY")
    if p:
        return p
    return config_root() / "policy.yaml"


def history_db_path() -> Path:
    p = _env_path("ZOMBIE_HISTORY_DB")
    if p:
        return p
    return state_root() / "conversations.db"


def pi_mono_log_dir() -> Path:
    p = _env_path("ZOMBIE_PI_MONO_LOG_DIR")
    if p:
        return p
    return state_root() / "logs"


def pi_mono_settings_path() -> Path:
    p = _env_path("ZOMBIE_PI_MONO_SETTINGS")
    if p:
        return p
    return install_root() / "pi" / "settings.json"


def builtin_skills_dir() -> Path:
    """Bundled skills shipped under the install root."""
    return install_root() / "skills"


def operator_skills_dir() -> Path:
    """Operator-extensible skills.d directory."""
    if _IS_WINDOWS:
        return config_root() / "skills.d"
    return Path("/etc/ubuntu-zombie/skills.d")


def bin_dir() -> Path:
    return install_root() / "bin"


def is_windows() -> bool:
    return _IS_WINDOWS
