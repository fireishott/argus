# Argus

A private-by-default model usage dashboard with a native macOS menu-bar client.

Argus gives you a compact read on provider quota windows, balances, resets, and health without placing credentials in the client. The web UI, macOS client, and future Kallisti integration all consume one redacted API contract.

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
```

**Hard boundary:** provider tokens, router passwords, database paths, cookies, request content, account identifiers, and raw provider responses stay server-side.

## Quick start

```bash
cp config/config.example.yaml config/config.yaml
# Edit only config/config.yaml for your local host, source paths, and enabled providers.
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python main.py
```

Credentials are passed by environment variables named in `config/config.yaml`. The real config file is ignored by git.

## Client API

See [docs/API.md](docs/API.md). The stable surface is:

- `GET /api/v1/health`
- `GET /api/v1/snapshot`

The snapshot is read-only and redacted. This is the only API macOS and Kallisti are allowed to consume.

## macOS client

`macos/ArgusMenuBar` is a Swift Package with a native `MenuBarExtra` client. It polls the v1 snapshot every 60 seconds, shows the first provider's remaining quota in the status bar, and opens a compact provider panel with all available windows and balances.

Configure the endpoint in the app's Settings surface when it lands. The API bearer token is intended for Keychain, never `UserDefaults`, source files, or git.

## Kallisti door

Argus is prepared for Kallisti without coupling it to a local database or provider credential. The future native connector calls the same versioned snapshot endpoint, applies Kallisti-side auth and notification policy, and presents data in the app. Details: [docs/API.md](docs/API.md).

## Public-readiness rules

- The repo is private at creation time, but code must be publishable without a scrub pass.
- `config/config.yaml`, `.env*`, credentials, databases, captures, and build output are ignored.
- Do not add real network addresses, tokens, personal information, or provider account details to docs, tests, screenshots, issues, or commits.
- Add a provider through a server adapter and `config.yaml`, never by baking a credential or local topology into the client.

## Status

Foundation branch. The existing Argus dashboard is being migrated into this configuration-driven, client-safe layout before its public release.

License intentionally deferred until the public release decision.
