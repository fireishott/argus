"""Machine-local Argus configuration.

Only `config/config.yaml` is loaded at runtime. The repository ships the
non-sensitive `config.example.yaml` template and ignores the real file.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = ROOT / "config" / "config.yaml"


def _deep_get(data: dict[str, Any], dotted_key: str, default: Any = None) -> Any:
    value: Any = data
    for part in dotted_key.split("."):
        if not isinstance(value, dict):
            return default
        value = value.get(part)
        if value is None:
            return default
    return value


class Settings:
    def __init__(self, raw: dict[str, Any]):
        self.raw = raw

    def get(self, dotted_key: str, default: Any = None) -> Any:
        return _deep_get(self.raw, dotted_key, default)

    def env_value(self, dotted_key: str) -> str:
        name = self.get(dotted_key, "")
        return os.environ.get(name, "") if isinstance(name, str) else ""


def load_settings() -> Settings:
    path = Path(os.environ.get("ARGUS_CONFIG", DEFAULT_CONFIG_PATH))
    if not path.exists():
        raise RuntimeError(
            f"Argus configuration is missing: {path}. "
            "Copy config/config.example.yaml to config/config.yaml and configure it."
        )
    with path.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}
    if not isinstance(raw, dict):
        raise RuntimeError("Argus configuration root must be a YAML mapping.")
    return Settings(raw)


settings = load_settings()
