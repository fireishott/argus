# Argus Public Snapshot API

This is the client contract for the macOS menu-bar app and the future Kallisti integration. It is deliberately narrow.

## Security boundary

The API returns computed usage data only. It never returns:

- Provider API keys, OAuth tokens, cookies, passwords, or database paths
- Account emails, organization IDs, connection IDs, or raw provider responses
- Request prompts, completions, model inputs, or user identifiers

The server keeps provider credentials and source adapters behind this boundary.

## Authentication

If `api.bearer_token_env` resolves to a value, clients send:

```http
Authorization: Bearer <token>
```

The token is held in Keychain on macOS and in Kallisti's existing secure credential path. It is never stored in this repository or emitted in logs.

## `GET /api/v1/health`

Returns a minimal availability response.

```json
{"ok":true,"schema_version":1,"service":"argus"}
```

## `GET /api/v1/snapshot`

Returns a stable, redacted view of usage and balances.

```json
{
  "schema_version": 1,
  "generated_at": "2026-08-13T00:00:00Z",
  "providers": [
    {
      "provider": "claude",
      "label": "Claude",
      "status": "active",
      "windows": [
        {
          "id": "5h",
          "label": "5h",
          "remaining_percent": 82,
          "reset_at": "2026-08-13T03:00:00Z"
        }
      ],
      "balance": {"kind":"credit","remaining":12.34,"currency":"USD"}
    }
  ],
  "summary": {"provider_count": 1, "low_quota_count": 0},
  "links": {"dashboard_url": null}
}
```

### Contract rules

- `remaining_percent` is 0 through 100, or omitted when a provider does not expose it.
- Values are rounded server-side. Currency never exceeds two decimals.
- `reset_at` is ISO 8601 UTC when known.
- A provider may have no windows and/or no balance.
- Unknown provider metrics are omitted rather than guessed.
- Clients must tolerate new fields and unknown providers.

## Kallisti seam

Kallisti should call only `/api/v1/health` and `/api/v1/snapshot` through its native connector/facade. It must not access Argus databases or provider endpoints directly. The connector owns auth, timeout, and push policy; Argus remains read-only.
