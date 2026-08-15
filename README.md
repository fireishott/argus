# Argus

A read-only model usage dashboard with a native macOS menu-bar client.

Argus gives you a compact read on provider quota windows, balances, resets,
and health without ever placing credentials in the client. The web dashboard,
macOS menu bar, and future Kallisti integration all consume one redacted API
contract served from your own host.

## Features

- **Provider usage at a glance** - Claude, Codex, DeepSeek, MiniMax, MiMo,
  OpenRouter, OpenCode, Gemini (Antigravity), and more via pluggable adapters.
- **Read-only, redacted API** - `GET /api/v1/snapshot` returns computed usage
  only. No tokens, cookies, database paths, account IDs, or raw upstream
  responses ever leave the server.
- **Native macOS menu bar** - pin individual quota windows and balances as
  separate status items in any order. Display as percentage, balance, usage
  bar, fuel gauge, or icon-only.
- **OAuth Connect** - sign in to Claude and Codex with real PKCE flows from
  the Settings panel. Tokens live in Keychain, never in files or git.
- **Balance threshold colors** - configurable dollar thresholds ($10 / $5 /
  $2.50 by default) drive yellow/orange/red balance text while icon color
  keeps reflecting availability and live traffic.
- **Live activity awareness** - menu bar icons show real green in-use state
  when the host ledger reports routed traffic, not a fake connection-green.
- **Local-first** - credentials stay in your Keychain or a mode-600
  environment file. No cloud, no telemetry, no accounts.

## Architecture

```text
Provider APIs / local usage store
            |
            v
     Argus server adapters
            |
            v
  /api/v1/snapshot (redacted)
      |                 |
      v                 v
macOS menu bar     Kallisti connector/plugin
      |
      v
 web dashboard (optional)
```

**Hard boundary:** provider tokens, router passwords, database paths,
cookies, request content, account identifiers, and raw provider responses
stay server-side.

## Quick start

```bash
cp config/config.example.yaml config/config.yaml
# Edit only config/config.yaml for your local host, source paths, and enabled providers.
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python main.py
```

Credentials are passed by environment variables named in `config/config.yaml`.
The real config file is ignored by git. On macOS you can enable
`local_first.keychain_credentials` and manage provider tokens from the
client's Settings panel instead.

## Client API

See [docs/API.md](docs/API.md). The stable surface is:

- `GET /api/v1/health`
- `GET /api/v1/snapshot`

The snapshot is read-only and redacted. This is the only API macOS and
Kallisti are allowed to consume. Optional bearer-token auth is configured via
`api.bearer_token_env` and held in Keychain on the client.

## macOS client

`macos/ArgusMenuBar` is a Swift Package with a native menu-bar client. It
polls the v1 snapshot at your chosen interval (5s / 15s / 60s), renders pinned
targets as independent status items, and opens a compact provider panel with
all available windows and balances.

- Hover a provider item: quick peek tooltip.
- Single-click a provider item: detail popover.
- Double-click a provider item: open Settings.
- The Argus control item is optional and removable from Settings.

Build with `swift build` inside `macos/ArgusMenuBar` on a Mac. The backend
runs anywhere Python 3.10+ runs.

## Supported providers

| Provider | Quota windows | Balance | Auth |
| --- | --- | --- | --- |
| Claude | 5h / 7d | - | OAuth (PKCE) or token |
| Codex (ChatGPT) | 7d / session | - | OAuth (PKCE) or token |
| DeepSeek | - | yes | API key |
| MiniMax | - | yes | API key |
| OpenRouter | - | yes | API key |
| OpenCode | - | - | API key |
| MiMo | - | - | session cookie |
| Gemini (Antigravity) | limited | - | CLI creds (BYOK) |

Provider list is config-driven; adapters are the only place upstream APIs are
touched.

## Kallisti door

Argus is prepared for Kallisti without coupling it to a local database or
provider credential. The future native connector calls the same versioned
snapshot endpoint, applies Kallisti-side auth and notification policy, and
presents data in the app. Details: [docs/API.md](docs/API.md).

## Status

Active development (v0.2.0). Argus is building toward a polished macOS
menu-bar monitor, a web dashboard, and a future Kallisti integration.
Pre-1.0 versions may evolve the API contract.

## License

[MIT](LICENSE).
