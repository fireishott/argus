"""Argus data layer - reads provider usage, rate limits, and balances.

Sources (all verified 2026-08-12):
- 9router SQLite DB (LIVE one, ignyte profile path): usageHistory,
  requestDetails, usageDaily, providerConnections tables. Argus must read the
  SAME DB the running gateway uses - the stale copy at ~/.9router/db/ is not it.
- 9router dashboard API (cookie auth) for live quota/rate-limit state
- Live balance/usage endpoints:
    OpenRouter  https://openrouter.ai/api/v1/auth/key
    DeepSeek    https://api.deepseek.com/user/balance
    MiniMax     https://www.minimax.io/v1/token_plan/remains  (5h + 7d windows)
                https://api.minimax.io/v1/api/openplatform/coding_plan/remains
    OpenCodeGo  https://opencode.ai/zen/go/v1/usage  (rolling 5h + weekly + monthly)
    MiMo (xiaomi-tokenplan): NO public quota endpoint - tp- key is chat-only,
    quota lives behind Xiaomi account login on platform.xiaomimimo.com
"""

import json
import os
import sqlite3
import urllib.request
import urllib.error
import datetime as dt
from http.cookiejar import CookieJar
from pathlib import Path

from config import settings

# Machine-specific data sources live only in config/config.yaml. The repository
# has no default host, database, account, or credential values.
ROUTER_URL = str(settings.get("sources.router.url", ""))
ROUTER_PASSWORD = settings.env_value("sources.router.password_env")
DB_PATH = Path(str(settings.get("sources.usage_store.sqlite_path", ""))).expanduser()


def _provider_credential(provider: str) -> str:
    return settings.env_value(f"sources.providers.{provider}.credential_env")


def _provider_enabled(provider: str) -> bool:
    return bool(settings.get(f"sources.providers.{provider}.enabled", False))

# Provider display names + whether they have a live balance API
PROVIDER_LABELS = {
    "claude": "Claude",
    "antigravity": "Antigravity",
    "deepseek": "DeepSeek",
    "xai": "xAI",
    "codex": "Codex",
    "xiaomi-tokenplan": "MiMo",
    "openrouter": "OpenRouter",
    "minimax": "MiniMax",
    "opencode-go": "OpenCode Go",
}


def _db_conn():
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def _configured_credentials():
    """Read provider credentials from the environment named by local config.

    Argus intentionally never mines credentials from usage stores or router
    databases. This keeps the public source tree and client contract clean.
    """
    return {
        provider: _provider_credential(provider)
        for provider in PROVIDER_LABELS
        if _provider_enabled(provider) and _provider_credential(provider)
    }


# ── Usage from 9router DB ─────────────────────────────────────────────────────

def usage_summary(days: int = 30):
    """Aggregate usageHistory: tokens + cost per provider/model over N days."""
    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)).isoformat()
    conn = _db_conn()
    rows = conn.execute(
        """SELECT provider, model,
                  COUNT(*) as requests,
                  SUM(promptTokens) as prompt_tokens,
                  SUM(completionTokens) as completion_tokens,
                  SUM(cost) as cost
           FROM usageHistory
           WHERE timestamp >= ?
           GROUP BY provider, model
           ORDER BY cost DESC""",
        (since,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def usage_by_day(days: int = 14):
    """Daily totals: requests, tokens, cost."""
    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)).isoformat()
    conn = _db_conn()
    rows = conn.execute(
        """SELECT substr(timestamp, 1, 10) as day,
                  COUNT(*) as requests,
                  SUM(promptTokens) as prompt_tokens,
                  SUM(completionTokens) as completion_tokens,
                  SUM(cost) as cost
           FROM usageHistory
           WHERE timestamp >= ?
           GROUP BY day
           ORDER BY day""",
        (since,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def totals():
    """Lifetime + today totals from usageHistory."""
    conn = _db_conn()
    lifetime = conn.execute(
        """SELECT COUNT(*) as requests,
                  SUM(promptTokens) as prompt_tokens,
                  SUM(completionTokens) as completion_tokens,
                  SUM(cost) as cost
           FROM usageHistory"""
    ).fetchone()
    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    today_row = conn.execute(
        """SELECT COUNT(*) as requests, SUM(cost) as cost
           FROM usageHistory WHERE substr(timestamp, 1, 10) = ?""",
        (today,),
    ).fetchone()
    conn.close()
    return {"lifetime": dict(lifetime), "today": dict(today_row)}


# ── Providers + rate limits from 9router API ─────────────────────────────────

class RouterAuth:
    """Cookie-auth session against 9router dashboard API."""

    def __init__(self):
        self.cookie_jar = None
        self._login()

    def _login(self):
        if not ROUTER_PASSWORD:
            self.cookie_jar = None
            return
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(CookieJar())
        )
        req = urllib.request.Request(
            f"{ROUTER_URL}/api/auth/login",
            data=json.dumps({"password": ROUTER_PASSWORD}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            opener.open(req, timeout=10)
            self.opener = opener
        except Exception:
            self.opener = None

    def get(self, path: str, timeout: int = 10):
        if not getattr(self, "opener", None):
            return None
        try:
            resp = self.opener.open(
                urllib.request.Request(f"{ROUTER_URL}{path}"), timeout=timeout
            )
            return json.loads(resp.read().decode("utf-8", errors="replace"))
        except Exception:
            return None


def _get_json(url: str, headers: dict, timeout: int = 15):
    """GET JSON with raw_decode fallback (9router responses carry SSE artifact).

    Sends a browser-ish User-Agent: some endpoints (opencode.ai) 403 the
    default urllib UA.
    """
    hdrs = dict(headers)
    hdrs.setdefault("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
    req = urllib.request.Request(url, headers=hdrs)
    raw = urllib.request.urlopen(req, timeout=timeout).read().decode(
        "utf-8", errors="replace"
    )
    return json.JSONDecoder().raw_decode(raw.strip())[0]


# ── Direct quota fetchers (providers with no 9router usage handler) ──────────

def _minimax_quota(api_key: str):
    """MiniMax token plan: 5h + 7d windows from token_plan/remains."""
    urls = [
        "https://www.minimax.io/v1/token_plan/remains",
        "https://api.minimax.io/v1/api/openplatform/coding_plan/remains",
    ]
    last_err = ""
    for u in urls:
        try:
            payload = _get_json(u, {"Authorization": f"Bearer {api_key}"})
        except Exception as e:
            last_err = str(e)
            continue
        br = payload.get("base_resp") or payload.get("baseResp") or {}
        if br.get("status_code"):
            return {"message": f"MiniMax: {br.get('status_msg','error')}"}
        models = payload.get("model_remains") or payload.get("modelRemains") or []
        quotas = {}
        captured = dt.datetime.now(dt.timezone.utc).timestamp() * 1000
        for m in models:
            name = str(m.get("model_name") or m.get("modelName") or "general")
            disp = "M-series" if name in ("general", "MiniMax-M*") else name
            for window, prefix in (("5h", "current_interval"), ("7d", "current_weekly")):
                total = m.get(f"{prefix}_total_count") or 0
                used = m.get(f"{prefix}_usage_count") or 0
                rem_pct = m.get(f"{prefix}_remaining_percent")
                remains_ms = m.get(f"{prefix}_remains_time")
                end = m.get(f"{prefix}_end_time")
                reset_at = None
                if remains_ms:
                    reset_at = dt.datetime.fromtimestamp(
                        (captured + remains_ms) / 1000, tz=dt.timezone.utc
                    ).isoformat()
                elif end:
                    reset_at = dt.datetime.fromtimestamp(
                        end / 1000, tz=dt.timezone.utc
                    ).isoformat()
                quotas[f"{disp} ({window})"] = {
                    "used": used or 0,
                    "total": total or 0,
                    "remaining": max((total or 0) - (used or 0), 0),
                    "remainingPercentage": rem_pct,
                    "resetAt": reset_at,
                    "unlimited": False,
                }
        if quotas:
            return {"quotas": quotas, "plan": "MiniMax Token Plan"}
        return {"message": "MiniMax connected. No quota data returned."}
    return {"message": f"MiniMax usage unavailable: {last_err}"}


def _opencode_quota(api_key: str):
    """OpenCode Go: rolling (5h) + weekly + monthly from zen usage API."""
    try:
        payload = _get_json(
            "https://opencode.ai/zen/go/v1/usage",
            {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        )
    except Exception as e:
        return {"message": f"OpenCode Go usage unavailable: {e}"}
    u = payload.get("usage") or {}
    quotas = {}
    for key, label in (("rolling", "session (5h)"), ("weekly", "weekly (7d)"), ("monthly", "monthly (30d)")):
        w = u.get(key)
        if not w or not isinstance(w, dict):
            continue
        pct = max(0, min(100, float(w.get("percent", 0) or 0)))
        quotas[label] = {
            "used": pct,
            "total": 100,
            "remaining": 100 - pct,
            "remainingPercentage": 100 - pct,
            "resetAt": w.get("resetsAt"),
            "unlimited": False,
        }
    if quotas:
        return {"quotas": quotas, "plan": "OpenCode Go"}
    return {"message": "OpenCode Go connected. No quota data returned."}


_CLAUDE_QUOTA_CACHE = {}


def _claude_quota(access_token: str):
    """Claude OAuth usage direct from Anthropic (bypasses 9router 429 cooldown).

    Endpoint shape (from 9router usage/claude.js): data.five_hour /
    data.seven_day with {utilization, resets_at}, plus data.extra_usage.
    utilization = % USED (0-100).

    Cached: Anthropic rate-limits this endpoint hard, and a transient 429
    must not blank the panel. Serve last-good data (flagged stale) on failure.
    """
    try:
        payload = _get_json(
            "https://api.anthropic.com/api/oauth/usage",
            {
                "Authorization": f"Bearer {access_token}",
                "anthropic-beta": "oauth-2025-04-20",
                "anthropic-version": "2023-06-01",
            },
        )
    except urllib.error.HTTPError as e:
        if e.code == 429 and _CLAUDE_QUOTA_CACHE:
            cached = dict(_CLAUDE_QUOTA_CACHE)
            cached["stale"] = True
            return cached
        if e.code == 429:
            return {"message": "Claude usage API rate-limited (429) - retry in a few min."}
        return {"message": f"Claude usage unavailable (HTTP {e.code})."}
    except Exception as e:
        if _CLAUDE_QUOTA_CACHE:
            cached = dict(_CLAUDE_QUOTA_CACHE)
            cached["stale"] = True
            return cached
        return {"message": f"Claude usage unavailable: {e}"}

    def quota_of(window):
        if not window or not isinstance(window, dict):
            return None
        used = window.get("utilization")
        if not isinstance(used, (int, float)):
            return None
        remaining = max(0, 100 - used)
        return {
            "used": used,
            "total": 100,
            "remaining": remaining,
            "remainingPercentage": remaining,
            "resetAt": window.get("resets_at"),
            "unlimited": False,
        }

    quotas = {}
    fh = quota_of(payload.get("five_hour"))
    if fh:
        quotas["session (5h)"] = fh
    wk = quota_of(payload.get("seven_day"))
    if wk:
        quotas["weekly (7d)"] = wk
    for key, value in payload.items():
        if key.startswith("seven_day_") and key != "seven_day":
            q = quota_of(value)
            if q:
                model_name = key.replace("seven_day_", "")
                quotas[f"weekly {model_name} (7d)"] = q
    if not quotas:
        return {"message": "Claude connected. No quota data returned."}
    result = {
        "plan": "Claude Code",
        "extraUsage": payload.get("extra_usage") or None,
        "quotas": quotas,
    }
    _CLAUDE_QUOTA_CACHE.update(result)
    return result


def _mimo_quota(session_cookie: str):
    """MiMo quota adapter using a locally supplied session cookie.

    Browser login and session renewal are intentionally outside Argus. Deployers
    inject the session value through the environment variable named in config.
    It is never written to disk or returned by the API.
    """
    if not session_cookie:
        return {"message": "MiMo: no local session configured"}
    base_url = str(settings.get("sources.providers.xiaomi-tokenplan.base_url", "")).rstrip("/")
    if not base_url:
        return {"message": "MiMo: endpoint is not configured"}
    headers = {"Cookie": session_cookie, "User-Agent": "Argus/1.0", "Accept": "application/json"}
    quotas = {}
    plan = None
    period_end = None
    try:
        detail = _get_json(f"{base_url}/tokenPlan/detail", headers)
        data = detail.get("data") or {}
        plan = data.get("planName")
        period_end = data.get("currentPeriodEnd")
        usage = _get_json(f"{base_url}/tokenPlan/usage", headers).get("data") or {}
        for source, label in ((usage.get("usage") or {}, "plan (12m)"), (usage.get("monthUsage") or {}, "month (30d)")):
            for item in source.get("items", []):
                limit, used = item.get("limit") or 0, item.get("used") or 0
                if not limit:
                    continue
                percent_used = float(item.get("percent") or (used / limit)) * 100
                quotas[label] = {"used": percent_used, "total": 100, "remaining": 100 - percent_used,
                                  "remainingPercentage": 100 - percent_used, "resetAt": period_end,
                                  "unlimited": False}
                break
    except Exception:
        return {"message": "MiMo usage unavailable"}
    return {"plan": plan or "MiMo Token Plan", "quotas": quotas} if quotas else {"message": "MiMo connected. No quota data returned."}

def providers():
    """Provider connections + live quota via 9router API (falls back to DB)."""
    auth = RouterAuth()
    api = auth.get("/api/providers") or {}
    conns = api.get("connections", [])

    if not conns:
        # Fallback: read connection list from DB
        conn = _db_conn()
        rows = conn.execute(
            "SELECT id, provider, authType, name, isActive FROM providerConnections"
        ).fetchall()
        conn.close()
        conns = [dict(r) for r in rows]

    keys = _configured_credentials()
    out = []
    for c in conns:
        provider = c.get("provider", "")
        item = {
            "id": c.get("id"),
            "provider": provider,
            "label": PROVIDER_LABELS.get(provider, provider.title()),
            "authType": c.get("authType", ""),
            "name": c.get("name", ""),
            "isActive": bool(c.get("isActive", True)),
            "testStatus": c.get("testStatus", "unknown"),
            "priority": c.get("priority"),
            "expiresAt": c.get("expiresAt"),
        }
        # Live quota from 9router usage handler
        if c.get("id"):
            quota = auth.get(f"/api/usage/{c['id']}")
            # Only trust the router's quota when it actually has window data;
            # a message-only dict (e.g. "Usage not available...") must not
            # shadow direct fetchers below.
            if quota and (quota.get("quotas") or quota.get("extraUsage")):
                item["quota"] = quota
        # Direct fetchers for providers with no 9router usage handler, or whose
        # router handler is message-only (Claude 429 cooldown).
        if provider == "opencode-go" and keys.get("opencode-go") and not item.get("quota"):
            item["quota"] = _opencode_quota(keys["opencode-go"])
        if provider == "claude" and keys.get("claude") and not item.get("quota"):
            item["quota"] = _claude_quota(keys["claude"])
        # MiMo: token-plan quota lives behind the Xiaomi platform console
        # (tp- key is chat-only). Uses the SSO/STS session from the MBP
        # MiMo session is injected through its configured local environment key.
        if provider == "xiaomi-tokenplan" and not item.get("quota"):
            item["quota"] = _mimo_quota(keys.get("xiaomi-tokenplan", ""))
        out.append(item)

    # MiniMax is not a providerConnection in the live DB; add it separately so
    # the 5h window shows even though the router doesn't track it as a provider.
    if keys.get("minimax"):
        mmq = _minimax_quota(keys["minimax"])
        if mmq.get("quotas"):
            out.append({
                "id": None,
                "provider": "minimax",
                "label": "MiniMax",
                "authType": "apikey",
                "name": "Token Plan",
                "isActive": True,
                "testStatus": "active",
                "priority": 90,
                "quota": mmq,
            })
    out.sort(key=lambda p: (p.get("priority") is None, p.get("priority") or 999))
    return out


# ── Live balances ─────────────────────────────────────────────────────────────

def balances():
    """Live balance/usage for providers that expose an endpoint."""
    keys = _configured_credentials()
    result = {}

    # OpenRouter: usage + limits from /api/v1/auth/key
    if keys.get("openrouter"):
        try:
            body = _get_json(
                "https://openrouter.ai/api/v1/auth/key",
                {"Authorization": f"Bearer {keys['openrouter']}"},
            )
            d = body.get("data", {})
            credits_remaining = None
            credits_total = None
            try:
                cbody = _get_json(
                    "https://openrouter.ai/api/v1/credits",
                    {"Authorization": f"Bearer {keys['openrouter']}"},
                )
                cd = cbody.get("data", {})
                if cd.get("total_credits") is not None and cd.get("total_usage") is not None:
                    credits_remaining = round(
                        float(cd["total_credits"]) - float(cd["total_usage"]), 2
                    )
                    credits_total = float(cd["total_credits"])
            except Exception:
                credits_remaining = None
                credits_total = None
            result["openrouter"] = {
                "label": "OpenRouter",
                "usage": d.get("usage"),
                "usage_daily": d.get("usage_daily"),
                "usage_weekly": d.get("usage_weekly"),
                "usage_monthly": d.get("usage_monthly"),
                "limit": d.get("limit"),
                "limit_remaining": d.get("limit_remaining"),
                "byok_usage": d.get("byok_usage"),
                "credits_remaining": credits_remaining,
                "credits_total": credits_total,
            }
        except Exception as e:
            result["openrouter"] = {"error": str(e)}

    # DeepSeek: balance
    if keys.get("deepseek"):
        try:
            body = _get_json(
                "https://api.deepseek.com/user/balance",
                {"Authorization": f"Bearer {keys['deepseek']}"},
            )
            infos = body.get("balance_infos", [])
            if infos:
                result["deepseek"] = {
                    "label": "DeepSeek",
                    "total_balance": infos[0].get("total_balance"),
                    "granted_balance": infos[0].get("granted_balance"),
                    "topped_up_balance": infos[0].get("topped_up_balance"),
                    "is_available": body.get("is_available"),
                }
        except Exception as e:
            result["deepseek"] = {"error": str(e)}

    # MiniMax: token plan 5h/7d windows (subscription, no dollar balance)
    if keys.get("minimax"):
        mmq = _minimax_quota(keys["minimax"])
        if mmq.get("quotas"):
            result["minimax"] = {
                "label": "MiniMax",
                "quota": mmq["quotas"],
                "plan": "Token Plan",
            }
        else:
            result["minimax"] = {
                "label": "MiniMax",
                "note": "Subscription plan - quota via token_plan API",
            }
    else:
        result["minimax"] = {"label": "MiniMax", "note": "Subscription plan"}

    # OpenCode Go: rolling/weekly/monthly usage
    if keys.get("opencode-go"):
        oq = _opencode_quota(keys["opencode-go"])
        if oq.get("quotas"):
            result["opencode-go"] = {
                "label": "OpenCode Go",
                "quota": oq["quotas"],
                "plan": "Go Plan",
            }
        else:
            result["opencode-go"] = {"label": "OpenCode Go", "note": "Subscription"}

    return result
