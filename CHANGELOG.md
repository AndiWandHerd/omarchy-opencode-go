# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- "Machine interface" section in both READMEs: documented record schema
  with stability promise, collector CLI, history format, and panel IPC, so
  external tools (routines, cron jobs, agent hooks) can consume quota data.

## [0.2.0]

### Added
- Incremental database scan: after one full pass, only rows near the scan
  watermark are re-read (SQL-side `json_extract` filter with LIKE pre-gates,
  10-minute overlap band); in-place token finalization is corrected rather
  than double-counted; corrupt/shrunk caches fall back to a full rescan.
- Database auto-resolution: explicit `OPENCODE_DB`/`OPENCODE_DATABASE` path
  → freshest `opencode-*.db` by WAL activity → `opencode.db`.
- `OPENCODE_API_BASE_URL` mirror override (https only, enforced) and
  `OPENCODE_API_KEY` last-resort key fallback.
- Explicit HTTP 429 handling with panel retry hint.
- Owner-only (0600) cache, state, and history files.

## [0.1.0] – initial public release

### Added
- `opencode-go` shell plugin (bar widget + panel): OpenCode Go quota with
  remaining dollars, per-window reset countdowns, token history by day and
  model — alongside the classic per-subscription meters.
- Quota collector (`collectors/omarchy-agent-usage-opencode-go`): official Go
  usage endpoint, Bearer key reused from opencode's `auth.json`, local token
  stats from `opencode.db` (read-only), systemd timer (5 min), atomic record
  writes, 48 h desktop notification (click opens the panel).
- Graduated bar-icon alarm: lights up when a billing window nears its reset
  while plenty of budget would expire unused (piecewise curve through
  60 %-left-at-half-time and 20 %-left-in-final-24 h).
- Even-pace benchmark ticks on every limit meter.
- Graduated meter colors (60/80/90) blended from the active theme.
- Per-window situation tags (`EXHAUSTED` / `LOW` / `OVER PACE` / `USE IT`).
- `RECOMMENDATION` section with up to two behavioral advice lines, including
  the daily burn rate needed to fully use an expiring window (`~$5.90/day
  to use it up`). No cheerful advice on top of explicit error states; cached
  fallback records keep full balance/advice/history behavior.
- Limit rows read as “26% · $44.40 left”: used percent plus remaining
  dollars per window, so absolutes never need mental math. (The earlier
  month-grid pace overview was removed again — it restated balance; spend
  history keeps sampling for future charts.)
- i18n: English + German + contributor locale template (`locales/`).
- Widget settings: language, popup toggle + interval, alarm toggle,
  graduated-colors toggle (via `omarchy bar set opencode-go …`).
- Docs: README (EN/DE), CONTRIBUTING, install/uninstall scripts, MIT license.
