# Contributing

## Adding a language

Panel strings live in `locales/<lang>.json`; collector strings live in the
`STRINGS` dict inside `collectors/omarchy-agent-usage-opencode-go` (same
keys where they overlap: window names, advice templates).

1. Copy `locales/en.json` to `locales/<lang>.json` (ISO 639-1 code).
2. Translate the **values only**. Keep every `{placeholder}` exactly as-is
   (`{spent}`, `{duration}`, `{count}`, …) — they are substituted at runtime.
3. Mirror the new strings in the collector's `STRINGS` dict under your
   language key (notification lines, status/help texts, advice templates).
4. If your language needs a `language` setting option, add it to the
   `language` enum in `manifest.json` and to `resolve_language()` in the
   collector.
5. Test: `omarchy bar set opencode-go language <lang>`, then open the panel
   and force a collector run; check headers, tags, tooltips, advice lines,
   and one notification (temporarily lower `popupIntervalHours` if needed —
   remember to set it back).

Keep tone consistent with the existing locales: short, imperative, no
exclamation marks. Duration compact form (`Xd Yh`, `Xh Ym`, `Xm`) is shared
across locales on purpose.

## Development loop

- Edit in this repo, then sync into the live install with `./install.sh`
  (idempotent) and apply QML with `omarchy restart shell`. Structural QML
  edits do not reliably hot-reload — always restart to verify.
- Validate before every PR: `omarchy plugin validate .` must exit 0.
- Collector QA: `--force` run must print exactly one JSON line on stdout
  (nothing else), exit 0 on all paths (live, bad key, missing DB), and never
  print the API key — grep the script and its stdout for the key value.
- Panel QA: open the panel, screenshot the Go tab (limits with remaining
  dollars, balance, recommendation, tags), and confirm the bar icon states.
- No secrets in the repo, no writes under `/usr/share/omarchy`, no writes to
  `opencode.db` (read-only SQLite only).

## Design notes for reviewers

- Record titles stay English on purpose: the panel's `windowSpanMs` parses
  them. Localized display titles map via the stable per-limit `key`.
- Dollar figures always derive from API percents, never from local cost
  (unreliable for Go server-side multipliers).
- The graduated alarm curve, pace margin (0.15), and color thresholds
  (60/80/90) are intentionally conservative defaults; per-user tuning lives
  in code constants, global behavior in widget settings.
