# Changelog

All notable changes to Argus are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Argus is in active development. Versions below 1.0.0 may change the API
contract without a major version bump.

## [Unreleased]

### Added

- Codex (ChatGPT/OpenAI OAuth) quota adapter. Pulls plan info and rate-limit
  windows from the ChatGPT backend API (`/wham/accounts/check` and
  `/wham/usage`) using the same token `codex` CLI authenticates with.
- Antigravity (Gemini CLI free tier) provider label and status handling.
- Codex brand SVG asset for the macOS client (with `command` SF Symbol
  fallback).
- Balance threshold color system in the macOS client: configurable
  warning/critical/exhausted dollar thresholds (defaults $10.00 / $5.00 /
  $2.50). Balance text renders yellow below warning, orange below critical,
  red below exhausted. Icon color stays independent.
- Unavailable provider icons now render with a red diagonal strikethrough
  overlay instead of tinting the whole icon red, preserving brand marks.
- Status bar color now evaluates the worst remaining percentage across ALL
  quota windows for a provider, not just the displayed window.

### Changed

- Provider detail popover tightened: fixed-width label column, color-coded
  remaining percents, reset timestamps, compact layout.
- Status bar composite rendering draws the base icon once and overlays the
  slash/bar/gauge rather than re-tinting per frame.

## [0.2.0] - 2026-08-13

### Added

- Config-driven read-only service with a stable public contract:
  `GET /api/v1/health` and `GET /api/v1/snapshot`.
- Snapshot payload: providers, quota windows, balances, summary, dashboard
  link. Redacted server-side; no tokens, cookies, DB paths, or account IDs
  ever leave the host.
- Local-first macOS runtime with Keychain-backed credentials and no
  background Keychain prompts (interactive save/remove only).
- Local provider configuration flow and dynamic credential refresh.
- Individual status bar targets: pin specific quota windows or balances as
  separate native `NSStatusItem`s in any left-to-right order.
- Explicit status bar layout editor (add/remove/reorder pins) with
  revision-gated migration so a first run with missing live data cannot lock
  in an empty strip.
- Status bar display modes: percentage, balance, usage bar, fuel gauge,
  icon-only. Per-mode vertical and rounded pill variants.
- Configurable refresh intervals (5s / 15s / 60s) with live re-read.
- Provider brand SVG assets (Claude, DeepSeek, MiMo, MiniMax, OpenCode,
  OpenRouter) with SF Symbol fallbacks, template-tinted for light/dark.
- Live provider activity signal in the snapshot (host-ledger backed) so the
  menu bar can show real in-use green state rather than faking it from
  connection health alone.
- Real OAuth Connect for Claude and Codex (PKCE + localhost loopback
  callback), tokens stored in Keychain. Gemini/MiMo documented honestly as
  not OAuth-capable.
- Provider detail interactions: hover quick peek, single-click detail
  popover, double-click opens Settings.
- Optional Argus control item, removable via persisted preference, with
  double-click fallback to Settings.
- Web dashboard (static single-page view of the snapshot).

### Fixed

- Menu bar balance formatting outside SwiftUI (USD dollar symbol, 2-decimal
  cap).
- String-formatted DeepSeek balance parsed and normalized to numeric.
- Unavailable providers stay selectable in the status bar target picker.
- Duplicate provider rendering and status target balance formatting.
- SVG template tinting (bake color into status item pixels; use
  `contentTintColor` where raster tint breaks).
- Background Keychain access removed from refresh and settings paths; no
  SecurityAgent prompts during unattended startup.
- Status item handlers isolated on the main actor (Swift 6 warnings).
- SwiftPM resource bundle works with the app entry point; packaged provider
  SVG assets resolve at runtime.
- Persistent Argus control item removed by default (migration flag).
- Claude "NA" renders as 0 available (red) with reset countdown in hover.
- OAuth `oauth` field is `var` so it appears in the memberwise initializer.
- Sendable warnings silenced in the OAuth engine (loopback server guarded by
  a state queue).

## [0.1.0] - 2026-08-12

### Added

- Initial Argus provider usage service with legacy dashboard endpoints.
- Basic provider quota collection and balance display.
- Menu bar client scaffolding with configurable provider controls.

[Unreleased]: https://github.com/fireishott/argus/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/fireishott/argus/releases/tag/v0.2.0
[0.1.0]: https://github.com/fireishott/argus/releases/tag/v0.1.0
