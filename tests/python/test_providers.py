"""Tests for the provider model-catalogue and selection helpers.

These exercise the ``/model`` chat command's Python backend
(``providers.list_models`` / ``current_model`` / ``set_active_model``
and the ``server.App`` ``models_info`` / ``set_model`` methods) using a
stub Node bridge so the real ``@earendil-works/pi-ai`` package is not
required.
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

STUB_BRIDGE = (
    Path(__file__).resolve().parents[1] / "fixtures" / "stub-pi-ai-bridge.mjs"
)

node_required = pytest.mark.skipif(
    shutil.which("node") is None, reason="node runtime not available"
)


@pytest.fixture
def providers(monkeypatch: pytest.MonkeyPatch):
    import providers as providers_mod

    monkeypatch.setenv("ZOMBIE_PI_AI_BRIDGE", str(STUB_BRIDGE))
    monkeypatch.delenv("ZOMBIE_MODEL", raising=False)
    monkeypatch.delenv("ZOMBIE_PROVIDER", raising=False)
    for spec in providers_mod._PI_AI_PROVIDERS:
        monkeypatch.delenv(spec.key_env, raising=False)
        if spec.model_env:
            monkeypatch.delenv(spec.model_env, raising=False)
    return providers_mod


def test_lmstudio_is_a_supported_provider(providers) -> None:
    assert "lmstudio" in providers.SUPPORTED_PROVIDERS


def test_active_provider_and_default_model(providers, monkeypatch) -> None:
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    assert providers.active_provider() == "openai"
    # No ZOMBIE_MODEL set -> the registry default for openai.
    assert providers.current_model() == "gpt-4o-mini"


def test_current_model_none_without_default(providers, monkeypatch) -> None:
    # openrouter has no default model; current_model resolves to None.
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openrouter")
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-test")
    assert providers.current_model() is None


def test_active_provider_raises_without_config(providers) -> None:
    with pytest.raises(providers.NoProviderConfigured):
        providers.active_provider()


def test_set_active_model_requires_non_empty(providers, monkeypatch) -> None:
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    with pytest.raises(ValueError):
        providers.set_active_model("   ")


@node_required
def test_list_models_via_bridge(providers, monkeypatch) -> None:
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    models = providers.list_models()
    ids = [m["id"] for m in models]
    assert ids == ["stub-small", "stub-large"]
    assert models[1]["reasoning"] is True
    assert models[1]["context_window"] == 200000


@node_required
def test_set_active_model_validates_against_catalogue(providers, monkeypatch) -> None:
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    provider, model = providers.set_active_model("stub-large")
    assert provider == "openai"
    assert model == "stub-large"
    # Selecting persists for this process so later resolution sees it.
    assert providers.current_model() == "stub-large"
    # An id outside the catalogue is rejected.
    with pytest.raises(ValueError):
        providers.set_active_model("does-not-exist")


@node_required
def test_server_models_info_and_set_model(monkeypatch, tmp_path) -> None:
    import sys

    monkeypatch.setenv("ZOMBIE_PI_AI_BRIDGE", str(STUB_BRIDGE))
    monkeypatch.setenv("ZOMBIE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("ZOMBIE_AUDIT_LOG", str(tmp_path / "audit.log"))
    monkeypatch.delenv("ZOMBIE_MODEL", raising=False)

    # Drop any cached copies so the agent modules recompute their state
    # paths under the conftest-provided AI_ZOMBIE_ROOT tmp dir.
    for mod in ("server", "audit", "paths", "history", "policy"):
        sys.modules.pop(mod, None)
    import server

    app = server.App()
    try:
        info = app.models_info()
        assert info["provider"] == "openai"
        assert [m["id"] for m in info["models"]] == ["stub-small", "stub-large"]

        result = app.set_model("stub-small")
        assert result == {"ok": True, "provider": "openai", "model": "stub-small"}
        assert app.models_info()["current"] == "stub-small"

        bad = app.set_model("nope")
        assert "error" in bad
    finally:
        app.history.close()
