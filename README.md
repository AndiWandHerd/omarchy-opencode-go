# OpenCode Go for Omarchy

An Omarchy shell plugin that puts your **OpenCode Go plan quota** in the top
bar: remaining dollars, reset countdowns, even-pace benchmarks, budget alarms,
and behavioral recommendations — plus token history by day and model.

![OpenCode Go panel](docs/screenshots/panel.png)
![Quota notification](docs/screenshots/notification.png)

## Features

- **Quota tab** in the agents panel: monthly dollar balance (of $60), three
  limit meters — rolling 5 h ($12), weekly ($30), monthly ($60) — each with a
  live reset countdown, plus local token stats (today, last 7 days, by model).
- **Two-tone bar-icon alarm**: teal when a billing window nears its reset
  while plenty of budget would expire unused (warns above 60 % left at half
  the window, tightening to 20 % left in the final 24 h) — time for the
  expensive models; red when a window is nearly exhausted (≥90 %) or the
  balance runs low. Cream means calm.
- **Stale-data warning**: if the record is older than 30 minutes (e.g. the
  timer stopped), the panel says so instead of silently showing old numbers.
- **Even-pace benchmark ticks** on every limit meter: where consumption would
  sit at a perfectly steady pace.
- **Graduated meter colors** blended from your theme (60/80/90).
- **Situation tags** per window (`EXHAUSTED` / `LOW` / `OVER PACE` / `USE IT`).
- **RECOMMENDATION section**: up to two behavioral advice lines
  (e.g. “Rolling exhausted — resets in 2h 37m. Prompt cheap until then.”).
- **Limit rows with remaining dollars**: every window reads as
  “26% · $44.40 left”, so absolutes never need mental math. (Spend history
  keeps sampling in the background for future charts.)
- **48 h popup**: a desktop notification with all figures at most once every
  48 hours; clicking it opens the panel.
- **i18n**: English + German included, more via contributor locales.
- **Settings** (no file editing): language, popup toggle + interval, alarm
  toggle, graduated-colors toggle.

## Requirements

- Omarchy 4.x with the shell (`omarchy-shell`)
- opencode with an active **Go plan** (the key in
  `~/.local/share/opencode/auth.json` is reused — read-only, never printed)

## Install

Recommended — straight from git (updates via `omarchy plugin update`):

```bash
omarchy plugin add https://github.com/AndiWandHerd/omarchy-opencode-go.git --enable --yes
./install.sh --yes   # from the cloned repo: collector + systemd timer
```

Manual:

```bash
git clone https://github.com/AndiWandHerd/omarchy-opencode-go.git
cd omarchy-opencode-go
./install.sh
```

The installer validates the plugin, installs the quota collector plus its
5-minute systemd timer, places the widget top-right, and offers to disable
the stock `omarchy.agents` panel (same providers, fewer features — keeping
both shows a duplicate icon). If QML changes ever fail to appear, apply them
with `omarchy restart shell`.

## Configuration

Everything lives in the widget's bar entry (`~/.config/omarchy/shell.json`):

```bash
omarchy bar set opencode-go language de
omarchy bar set opencode-go popupIntervalHours 24 --json
omarchy bar set opencode-go popupEnabled Off
omarchy bar set opencode-go leftoverAlarm Off
omarchy bar set opencode-go graduatedColors Off
```

| Key | Default | What it does |
|---|---|---|
| `language` | `"auto"` | Panel + notification language (`auto` follows the system locale; `en`, `de`) |
| `popupEnabled` | `"On"` | 48 h quota notification on/off |
| `popupIntervalHours` | `48` | Minimum hours between popups |
| `leftoverAlarm` | `"On"` | Bar-icon alarm for expiring-unused budget on/off |
| `graduatedColors` | `"On"` | Warm meter colors on/off |

The collector reads the same entry, so there is exactly one place to
configure. No API keys are ever stored here — auth stays in opencode's
`auth.json`.

Optional environment for the collector (all unset by default):

| Variable | What it does |
|---|---|
| `OPENCODE_GO_API_KEY` | Key override (first choice, before `auth.json`) |
| `OPENCODE_API_KEY` | Last-resort fallback when no key was found elsewhere |
| `OPENCODE_API_BASE_URL` | Mirror/proxy base instead of `https://opencode.ai` — must be `https://`, otherwise the collector refuses to send the key |
| `OPENCODE_DB` / `OPENCODE_DATABASE` | Explicit database path instead of auto-resolution |

## How it works

Every 5 minutes a systemd user timer runs the collector
(`collectors/omarchy-agent-usage-opencode-go`), which queries the official Go
usage endpoint (`GET https://opencode.ai/zen/go/v1/usage`) with your existing
key, derives remaining dollars from the reported percents, scans your local
`opencode.db` read-only for token stats, and writes one JSON record to
`~/.local/state/omarchy/agents/usage/opencode-go.json`. The panel watches
that directory and renders whatever appears — the same extension point the
stock agents panel documents. Spend history keeps sampling alongside
(`opencode-go-history.jsonl`) for future charts.

The database scan is incremental: after one full pass, only rows near the
scan watermark are re-read (10-minute overlap band, in-place token
finalization is corrected rather than double-counted); the database is
auto-resolved (explicit path → freshest `opencode-*.db` by WAL activity →
`opencode.db`). Caches are owner-only (0600). HTTP 429 answers set a retry
hint instead of failing.

## Machine interface

Other tools can consume the same data the panel renders — a daily routine
checking whether budget should be spent, a cron nudge, or an agent hook.
Three seams, no extra dependencies:

**1. Record file (recommended for polling)** —
`~/.local/state/omarchy/agents/usage/opencode-go.json`, refreshed every
5 minutes by the systemd timer. One JSON object:

- `schemaVersion` (currently 1), `id` (`"opencode-go"`), `name`,
  `updatedAt` (ISO-8601 of the last collector run)
- `limits[]`: per window `{label, title, key ("rolling"|"weekly"|"monthly"),
  percent (0–1 used fraction), limit (USD allowance), resetsAt (ISO)}`
- `balance`: monthly dollars `{remaining, funded, spent, currency,
  estimated}` (`estimated` because the API reports whole percents)
- `advice[]`: up to two `{text, tone}` behavioral lines; `tone` is `good`
  (spend), `bad` (danger), or `info` (calm) — the machine-readable
  "should I spend?" signal
- Token stats: `todayPrompts/Sessions/TotalTokens/TokensByModel`,
  `recentDays[]` (7× `{date, messageCount}` in tokens), `modelUsage{}`,
  `totalPrompts/Sessions`, `activeDays/Dates`
- `ready`, `tierLabel`, `usageStatusText`/`authHelpText` (non-empty when the
  quota fetch failed; local stats still present)

Stability promise: fields are additive; a breaking change bumps
`schemaVersion`. Spend check in one line:

```bash
tone=$(jq -r '.advice[0].tone // "info"' ~/.local/state/omarchy/agents/usage/opencode-go.json)
[ "$tone" = good ] && jq -r '.advice[0].text' ~/.local/state/omarchy/agents/usage/opencode-go.json
```

**2. Collector CLI (fresh on-demand checks)** —
`omarchy-agent-usage-opencode-go [--force] [--limits-only]` prints exactly
one JSON line (same schema) to stdout and nothing else. Exit code is always
0 (errors ride in `usageStatusText`); validate with `jq -e .`.

**3. History (time series)** —
`~/.local/state/omarchy/agents/opencode-go-history.jsonl`, one line per
fresh probe: `{"t": ms-epoch, "rolling": %, "weekly": %, "monthly": %,
"resets": {...}}` (percents 0–100 used). For charts and pace math.

**4. Panel IPC (control, not data)** —
`omarchy-shell opencode-go <open|close|toggle|refresh|next>` drives the
panel, e.g. as `--exec` target for notification clicks.

## Languages

English and German ship in `locales/`. To add yours: copy `locales/en.json`,
translate the values (keep `{placeholders}` intact), and open a PR — see
[CONTRIBUTING](CONTRIBUTING.md).

## Uninstall

```bash
./uninstall.sh            # keeps your history/state
./uninstall.sh --purge    # removes history/state/caches too
```

## Upstream notes

The quota collector follows the stock `omarchy-agent-usage-*` contract, so
the Go tab also renders on the *stock* agents panel (without the deluxe
extras). Whether upstream wants the collector in-tree is tracked in
[docs/upstream-discussion-draft.md](docs/upstream-discussion-draft.md).

## Related work

- [markbus-ai/omarchy-opencode-usage](https://github.com/markbus-ai/omarchy-opencode-usage) —
  the sibling OpenCode usage widget for the Omarchy bar (token stats plus Go
  plan meters). Its incremental watermark scan inspired our v0.2.0 scan core.
- [FidelVillaRod/opencode-omarchy-plugin](https://github.com/FidelVillaRod/opencode-omarchy-plugin) —
  complementary rather than competing: session management (resume/export/
  delete, model picker) where this plugin does quota depth. The two run side
  by side without conflict.

## License

MIT — see [LICENSE](LICENSE).
