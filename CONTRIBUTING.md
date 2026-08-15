# Contributing to Argus

The more the merrier. Join the Argus pool party.

Argus is a small project with a simple goal: give you a clean read on your
model provider usage without giving your credentials to anyone. It runs on
your own host, reads provider APIs, and serves a redacted snapshot to a
menu-bar client. There is a lot of room to grow, and you do not need to be a
macOS expert to help.

## Ways to jump in

### Add a provider adapter

New model providers show up constantly. If you use one Argus does not support
yet, the adapter pattern is straightforward:

1. Look at `argus_data.py` - each provider has a `_<provider>_quota()`-style
   function that hits the provider's usage/balance API.
2. Add your provider to `PROVIDER_LABELS` and the `providers()` loop.
3. Add an entry to `config/config.example.yaml` with a `credential_env` for
   its secret.
4. Add the provider's row to the README table.
5. If you have an SVG brand mark for the menu bar, drop it in
   `macos/ArgusMenuBar/Sources/ArgusMenuBar/Resources/icons/` and register it
   in `ProviderIcon.assetNames`.

Rules that keep Argus safe:

- **Never** store credentials in the repo. Providers read tokens from
  environment variables or Keychain at runtime.
- **Never** leak raw upstream responses into the snapshot. The API contract
  is redacted and read-only. If the provider returns account IDs, cookies, or
  request content, keep it server-side.
- Keep balance values normalized to numeric USD with two decimals max.

### Port the client to another OS

The server is plain Python (FastAPI) and runs anywhere. The menu-bar client is
currently macOS-only. A Linux system tray client or a Windows tray client
would make Argus a real cross-platform tool. The API contract in
`docs/API.md` is the spec - build a client against `/api/v1/health` and
`/api/v1/snapshot` and it will work against any Argus server.

The macOS client lives in `macos/ArgusMenuBar` (Swift Package). The web
dashboard in `static/` is a useful reference for how the snapshot renders.

### Improve the dashboard, docs, or tests

- The web dashboard is a single `static/index.html` - easy to polish.
- The API docs live in `docs/API.md`.
- Bugs, edge cases, and weird provider responses are all fair game.

## Project structure

```text
main.py                 FastAPI service
argus_data.py           Provider adapters (quota + balance collection)
api_contract.py         Redacted snapshot contract
config.py               Config loading
config/config.example.yaml
docs/API.md             Client contract spec
static/                 Web dashboard
macos/ArgusMenuBar/     Native macOS menu-bar client (Swift)
```

## Pull request flow

1. Fork the repo and create a branch: `git checkout -b feat/your-thing`.
2. Make your change. Keep it small and focused - one provider or one fix per
   PR is perfect.
3. Verify locally: run the server, hit `/api/v1/health` and
   `/api/v1/snapshot`, confirm your adapter returns sane data and no secrets
   appear in the payload.
4. Open the PR. Say what you changed and how you tested it.

## House rules

- No credentials in the repo, ever. Real config lives in `config/config.yaml`
  and is gitignored.
- The snapshot API stays read-only and redacted. No exceptions.
- Money values: two decimals max.
- No em dashes in docs or commit messages. Use a regular hyphen.

## Code of conduct

Keep it chill. Be kind, assume good intent, and remember everyone here is
volunteering their time. Harassment of any kind is not welcome.

Questions? Open an issue. The pool is warm.
