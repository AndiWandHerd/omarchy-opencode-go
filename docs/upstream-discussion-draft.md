# Upstream drafts (basecamp/omarchy)

Per the contributing guide, feature ideas go to
https://github.com/basecamp/omarchy/discussions/categories/suggestions
(English). Drafts below — NOT yet posted.

## D1 — Opencode usage collector: in-tree or external?

> **Title:** Opencode (Go) usage collector for the agents panel?
>
> **Body:**
> I built an `omarchy-agent-usage-opencode`-style collector that feeds the
> agents panel a new tab: it queries the official Go usage endpoint
> (`GET https://opencode.ai/zen/go/v1/usage`) with the key opencode already
> stores in `~/.local/share/opencode/auth.json`, derives remaining dollars
> from the reported percents (rolling $12/5h, weekly $30, monthly $60), and
> adds local token stats from `opencode.db` (read-only). It prints exactly
> the documented record contract, so the stock panel renders it with zero
> panel changes (verified with screenshots).
>
> Question before I open a PR: do you want provider collectors like this
> in-tree (next to claude/codex/fireworks), or do you prefer them as
> external plugins (installed via `omarchy plugin add`)? Happy to shape the
> PR either way — including trimming it to limits+balance+stats only.

## D2 — Agents panel enhancement proposals (if D1 lands external or in-tree)

Independent, small, demoable PRs — each with before/after screenshots:

1. **`advice` record field + RECOMMENDATION section.** Collectors may ship
   up to two `{text, tone}` behavioral lines (`bad`/`good`/`info`); the
   panel renders them under a RECOMMENDATION header. Unknown to old
   collectors (section hides), ignored by old panels (unknown field).
2. **Per-window situation tags.** `EXHAUSTED` / `LOW` / `OVER PACE` in
   urgent, `USE IT` in accent when budget would expire unused — derived
   from percent + reset, no record changes.
3. **Even-pace benchmark ticks.** A tick on each limit meter at the elapsed
   window fraction, so usage reads against steady pace at a glance.
4. **Graduated meter colors.** Theme-blended foreground→urgent steps at
   60/80/90 (display only; alarm semantics untouched).
5. **Leftover-budget bar alarm.** Icon lights when a ≥7-day window nears
   reset with plenty unspent (piecewise curve, same predicate as the
   USE IT tag).
6. **Monthly pace overview.** Month-grid strip (spent day-equivalents plus
   today marker) with a one-line pace projection (`$44.40 · 9d left ·
   0.4× pace`) — needs no history, readable at a glance. Spend history
   sampling continues in the background for future charts.

Each proposal keeps stock behavior identical when the new record fields are
absent, so existing claude/codex/fireworks tabs render exactly as today.
