"""Public, redacted API contract shared by Argus clients."""

from __future__ import annotations

import datetime as dt
from typing import Any


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _remaining_percent(window: dict[str, Any]) -> int | None:
    value = window.get("remainingPercentage")
    if value is None:
        total = window.get("total")
        used = window.get("used")
        if isinstance(total, (int, float)) and total > 0 and isinstance(used, (int, float)):
            value = 100 - (used / total * 100)
    if not isinstance(value, (int, float)):
        return None
    return max(0, min(100, round(value)))


def _window_id(label: str) -> str:
    lowered = label.lower()
    if "5h" in lowered or "session" in lowered or "rolling" in lowered:
        return "5h"
    if "7d" in lowered or "week" in lowered:
        return "7d"
    if "month" in lowered or "30d" in lowered:
        return "month"
    if "year" in lowered or "12m" in lowered or "plan" in lowered:
        return "plan"
    return "usage"


def _balance(provider: str, balances: dict[str, Any]) -> dict[str, Any] | None:
    item = balances.get(provider)
    if not isinstance(item, dict) or item.get("error"):
        return None
    for key in ("credits_remaining", "limit_remaining", "total_balance"):
        value = item.get(key)
        if value is None:
            continue
        try:
            amount = float(str(value))
        except ValueError:
            continue
        return {"kind": "credit", "remaining": round(amount, 2), "currency": "USD"}
    return None


def snapshot(
    providers: list[dict[str, Any]], balances: dict[str, Any], dashboard_url: str = "", active_providers: set[str] | None = None
) -> dict[str, Any]:
    active_providers = active_providers or set()
    public_providers: list[dict[str, Any]] = []
    status_targets: list[dict[str, Any]] = []
    low_quota_count = 0
    for provider in providers:
        key = str(provider.get("provider") or "")
        if not key:
            continue
        # Providers can return the same quota window once per model bucket.
        # Argus presents one actionable row per window and keeps the lowest
        # remaining value, which is the constrained value the user needs to see.
        windows_by_id: dict[str, dict[str, Any]] = {}
        quota = provider.get("quota") or {}
        for label, window in (quota.get("quotas") or {}).items():
            if not isinstance(window, dict):
                continue
            remaining = _remaining_percent(window)
            window_id = _window_id(str(label))
            entry = {"id": window_id, "label": str(label)}
            if remaining is not None:
                entry["remaining_percent"] = remaining
            if window.get("resetAt"):
                entry["reset_at"] = str(window["resetAt"])
            current = windows_by_id.get(window_id)
            if current is None or (remaining is not None and remaining < current.get("remaining_percent", 101)):
                windows_by_id[window_id] = entry
        windows = list(windows_by_id.values())
        low_quota_count += sum(1 for window in windows if window.get("remaining_percent", 101) <= 15)
        status = "active" if provider.get("isActive", True) else "inactive"
        if provider.get("testStatus") not in (None, "unknown", "active"):
            status = "degraded"
        if status == "active" and key in active_providers:
            status = "in_use"
        item: dict[str, Any] = {
            "provider": key,
            "label": str(provider.get("label") or key),
            "status": status,
            "windows": windows,
        }
        balance = _balance(key, balances)
        if balance:
            item["balance"] = balance
        public_providers.append(item)

        # Status-bar targets intentionally retain the source label. A provider
        # may expose separate model buckets with the same 5h/7d category.
        # The popover condenses those into one row; the status bar lets the user
        # choose the exact bucket they care about.
        aggregate = next((window.get("remaining_percent") for window in windows if window.get("id") == "5h"), None)
        if aggregate is None and windows:
            aggregate = windows[0].get("remaining_percent")
        status_targets.append({
            "id": f"provider:{key}", "provider": key, "kind": "provider",
            "label": str(item["label"]), "remaining_percent": aggregate, "status": status,
        })
        for label, window in (quota.get("quotas") or {}).items():
            if not isinstance(window, dict):
                continue
            remaining = _remaining_percent(window)
            if remaining is None:
                continue
            normalized = str(label).lower().replace(" ", "-").replace("/", "-").replace("(", "").replace(")", "")
            status_targets.append({
                "id": f"window:{key}:{normalized}", "provider": key, "kind": "window",
                "label": f"{item['label']} - {label}", "remaining_percent": remaining, "status": status,
            })
        if balance:
            status_targets.append({
                "id": f"balance:{key}", "provider": key, "kind": "balance",
                "label": f"{item['label']} - balance", "balance": balance, "status": status,
            })

    return {
        "schema_version": 1,
        "generated_at": _utc_now(),
        "providers": public_providers,
        "status_targets": status_targets,
        "summary": {"provider_count": len(public_providers), "low_quota_count": low_quota_count},
        "links": {"dashboard_url": dashboard_url or None},
    }
