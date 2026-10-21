import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "opencode-go"
  ipcTarget: "opencode-go"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  // A window whose reset is near while plenty of budget would go to waste
  // lights the icon too — the mirror image of running dry. The curve is a
  // graduated staffel over remaining time fraction t: warn above 60% left at
  // half the window (t=0.5), tightening to above 20% left in the final day
  // (t=1/30), reaching any leftover at expiry. Weekly and monthly windows
  // only; the rolling rate-limit window is pace noise, never budget expiry.
  // Evaluated across ALL providers, not just the selected tab.
  function leftoverCurve(t) {
    if (t >= 1.0) return 1.0
    if (t >= 0.5) return 0.6 + 0.8 * (t - 0.5)
    if (t >= 0.0333) return 0.2 + (0.4 / 0.4667) * (t - 0.0333)
    if (t <= 0.0) return 0.0
    return 0.2 * (t / 0.0333)
  }
  function leftoverAlarmingFor(p) {
    if (!p) return false
    var windows = limitWindows(p)
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var span = windowSpanMs(w.title)
      if (span < 7 * 24 * 3600 * 1000) continue
      var remainingMs = resetMsFor(w)
      if (remainingMs <= 0) continue
      var t = remainingMs / span
      if (1 - w.percent > leftoverCurve(t)) return true
    }
    return false
  }
  readonly property bool leftoverAlarming: {
    if (setting("leftoverAlarm", "On") === "Off") return false
    for (var i = 0; i < providers.length; i++)
      if (leftoverAlarmingFor(providers[i])) return true
    return false
  }
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming
  // Opportunity vs danger: leftover budget near reset paints the icon accent
  // teal ("spend it"), while an exhausted window stays urgent red. Cream
  // means calm. The stock ≥90 % and balance alarms keep their red.
  readonly property bool opportunity: !alarming && leftoverAlarming
  // Record age: the collector stamps updatedAt on every write (5-minute
  // cadence). Older than 30 minutes means the timer likely stopped — say so
  // instead of silently showing yesterday's numbers.
  readonly property double recordAgeMs: {
    if (!provider) return 0
    var ts = Date.parse(String(provider.updatedAt || ""))
    if (!isFinite(ts)) return 0
    return Math.max(0, root.nowMs - ts)
  }
  readonly property bool recordStale: recordAgeMs > 30 * 60 * 1000
  // Per-window situation tag key for the limit rows: exhausted / low / over
  // in urgent red, expiring in accent when budget would expire unused (same
  // predicate as the bar-icon alarm, plus a 14-day imminence gate so the teal
  // tag is scarce and means "act now", not "someday"). Healthy windows stay
  // untagged. The tag text itself is localized at the call site via
  // tr("tag." + key).
  function windowSituation(w) {
    if (!w) return { tag: "", color: root.dim }
    var u = Number(w.percent)
    if (u >= 0.995) return { tag: "exhausted", color: root.urgent }
    if (u >= 0.9) return { tag: "low", color: root.urgent }
    var span = windowSpanMs(w.title)
    var remainingMs = resetMsFor(w)
    if (span > 0 && remainingMs > 0) {
      var t = remainingMs / span
      if (t > 0 && t < 1) {
        if (u - (1 - t) > 0.15) return { tag: "over", color: root.urgent }
        if (span >= 7 * 24 * 3600 * 1000 && (1 - u) > leftoverCurve(t)
            && remainingMs <= 14 * 24 * 3600 * 1000)
          return { tag: "expiring", color: Color.accent }
      }
    }
    return { tag: "", color: root.dim }
  }
  // Value-line tone for the "26% · $44.40 left" readout: urgent red when the
  // window is nearly gone or burning too fast, accent teal when budget
  // genuinely expires soon, foreground otherwise. Pure display — the alarm
  // flag itself still flips only on its own predicates.
  function limitValueTone(w) {
    var sit = windowSituation(w)
    if (sit.tag === "exhausted" || sit.tag === "low" || sit.tag === "over") return "bad"
    if (sit.tag === "expiring") return "good"
    return "calm"
  }
  // Behavioral recommendation lines from the collector (see Main.qml
  // advice pass-through): up to two {text, tone} entries.
  readonly property var adviceLines: provider ? (provider.advice || []) : []
  function adviceColor(tone) {
    if (tone === "bad") return root.urgent
    if (tone === "good") return Color.accent
    return root.dim
  }
  // Channel-wise blend between two theme colors. Used for the graduated
  // consumption scale below; Qt.tint would do, but explicit math leaves no
  // doubt about argument order.
  function blendColors(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  // Graduated consumption colors for limit meters: steady foreground below
  // 60%, warming toward urgent through 60% and 80%, urgent red at the 90%
  // alarm line. Blended from the theme's own foreground/urgent so the scale
  // survives theme switches (no fixed hues). Display only — the alarm flag
  // itself still flips at 90%.
  function limitMeterColor(percent, alarming) {
    if (alarming) return root.urgent
    if (!(percent >= 0)) return root.foreground
    if (percent >= 0.8) return blendColors(root.foreground, root.urgent, 0.65)
    if (percent >= 0.6) return blendColors(root.foreground, root.urgent, 0.4)
    return root.foreground
  }
  // Even-usage benchmark: the fraction of the window already elapsed, i.e.
  // where consumption would sit at a perfectly steady pace. Used as the tick
  // position on limit meters; -1 hides the tick (unknown span or reset).
  function evenPaceMarker(w) {
    if (!w) return -1
    var span = windowSpanMs(w.title)
    if (!(span > 0)) return -1
    var remainingMs = resetMsFor(w)
    if (!(remainingMs > 0)) return -1
    var elapsed = 1 - remainingMs / span
    if (!(elapsed > 0) || !(elapsed < 1)) return -1
    return elapsed
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Widget settings from the bar entry in shell.json (see manifest schema),
  // with the manifest defaults as fallback.
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ------------------------------------------------------------ i18n
  //
  // Panel language: the `language` setting ("auto", "en", "de"); "auto"
  // follows the system locale. Strings live in locales/<lang>.json next to
  // this file (English doubles as the key inventory for translators).
  // tr() falls back to English, then to the key itself.
  readonly property string lang: {
    var configured = String(setting("language", "auto")).toLowerCase()
    if (configured === "de" || configured === "en") return configured
    var sys = String(Quickshell.env("LANG") || Quickshell.env("LANGUAGE") || "en").toLowerCase()
    return sys.indexOf("de") === 0 ? "de" : "en"
  }
  property var stringsEn: ({})
  property var stringsSel: ({})

  function localeFilePath(lang) {
    return String(Qt.resolvedUrl("locales/" + lang + ".json")).replace(/^file:\/\//, "")
  }
  function parseLocale(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") return parsed
    } catch (e) {}
    return {}
  }
  function tr(key) {
    if (stringsSel && stringsSel[key] !== undefined) return stringsSel[key]
    if (stringsEn && stringsEn[key] !== undefined) return stringsEn[key]
    return key
  }
  function fmt(template, values) {
    var out = String(template || "")
    if (values) for (var name in values) out = out.split("{" + name + "}").join(String(values[name]))
    return out
  }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title, key, limit) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      key: String(key || ""),
      limit: Number(limit) || 0
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title, entry.key, entry.limit))
    }
    return out
  }

  // Localized window title for display. Records keep English titles because
  // windowSpanMs parses them; display maps the stable key instead. Records
  // without a key (other collectors) keep their parsed title.
  function windowDisplayTitle(w) {
    if (!w) return ""
    var key = String(w.key || "")
    if (key !== "") {
      var localized = tr("window." + key)
      if (localized !== "window." + key) return localized
    }
    return String(w.title || "")
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = fmt(tr("balance.detail"), { spent: formatMoney(b.spent, b.currency), funded: formatMoney(b.funded, b.currency) })
    if (b.estimated) text += " · " + tr("balance.estimated")
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return tr("hero.subscription")
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return [tr("day.sun"), tr("day.mon"), tr("day.tue"), tr("day.wed"), tr("day.thu"), tr("day.fri"), tr("day.sat")][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return tr("day.today")
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " " + tr("unit.tokens")
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " " + tr("unit.prompts") + " · "
        + Number(provider.todaySessions || 0) + " " + tr("unit.sessions")
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return tr("tooltip.in") + " " + usage.formatTokenCount(row.input)
      + " · " + tr("tooltip.out") + " " + usage.formatTokenCount(row.output)
      + " · " + tr("tooltip.cacheRead") + " " + usage.formatTokenCount(row.cacheRead)
      + " · " + tr("tooltip.cacheWrite") + " " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return fmt(provider.syncDeviceCount === 1 ? tr("sync.merged.one") : tr("sync.merged.other"), { count: provider.syncDeviceCount })
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  FileView {
    id: localeEnFile
    path: localeFilePath("en")
    watchChanges: false
    printErrors: false
    onLoaded: root.stringsEn = root.parseLocale(text())
  }

  FileView {
    id: localeSelFile
    path: localeFilePath(root.lang)
    watchChanges: false
    printErrors: false
    onLoaded: root.stringsSel = root.parseLocale(text())
  }

  onLangChanged: localeSelFile.reload()

  // Limit value readout: used percent plus remaining dollars, so both the
  // pace and the absolute budget read off one line ("26% · $44.40 left").
  // Windows without a dollar limit (other collectors) keep percent only.
  // Plan windows are USD-denominated; formatMoney keeps currency in one place.
  function limitValueText(w) {
    if (!w || !(Number(w.percent) >= 0)) return "—"
    var label = Math.round(Number(w.percent) * 100) + "%"
    var limit = Number(w.limit)
    if (!(limit > 0)) return label
    var remaining = Math.max(0, (1 - Number(w.percent)) * limit)
    return fmt(tr("limits.value"), { percent: label, remaining: formatMoney(remaining, "USD") })
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  // Always on (not just while opened): the bar-icon alarm reads resetMsFor,
  // which needs a live nowMs even when the panel is closed.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    foreground: root.opportunity ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan ----------
          PanelHero {
            id: hero
            visible: !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                // Provider objects are rebuilt on every refresh, which churns the
                // array's identity without changing its content. Restart the fallback
                // walk only when the URLs change: re-pointing source at a URL whose
                // load already failed emits no statusChanged, so an identity-only
                // reset would strand the walker on a missing -light twin.
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  // Advancing source from inside its own status change trips the
                  // binding-loop detector; defer the step one tick.
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: tr("empty.title") + "\n" + tr("empty.subtitle")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.recordStale
            width: parent.width
            topPadding: Style.space(2)
            text: root.fmt(root.tr("stale.message"), { duration: root.formatDuration(root.recordAgeMs) })
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Recommendation ----------
          Column {
            id: adviceSection
            visible: root.adviceLines.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              width: parent.width
              text: tr("section.recommendation")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.adviceLines

              Text {
                required property var modelData
                textFormat: Text.PlainText
                width: adviceSection.width
                text: String(modelData.text || "")
                color: root.adviceColor(String(modelData.tone || ""))
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: adviceSection.visible || balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: tr("section.balance")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: tr("balance.prepaid")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: tr("section.limits")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              width: parent.width
              text: tr("section.tokensDay")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: usageSection.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / usageSection.peak
                // By date, not by position: the Claude stats-cache fallback can
                // hand us a window that stops short of today.
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          // ---------- Models ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: tr("section.tokensModel")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                // Scaled to the heaviest model, so the top row is always full —
                // the same scale-to-peak the weekly chart uses for its busiest day.
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, reset countdown, and a
  // situation tag (EXHAUSTED / LOW / OVER PACE / USE IT) when relevant.
  component LimitRow: Column {
    id: limitRow
    property var window: null
    readonly property var situation: root.windowSituation(limitRow.window)

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: root.windowDisplayTitle(limitRow.window)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: root.limitValueText(limitRow.window)
        color: root.limitValueTone(limitRow.window) === "bad" ? root.urgent
          : root.limitValueTone(limitRow.window) === "good" ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
      marker: root.evenPaceMarker(limitRow.window)
      graduated: root.setting("graduatedColors", "On") !== "Off"
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? root.fmt(root.tr("limits.resetIn"), { duration: root.formatDuration(remainingMs) }) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      text: limitRow.situation.tag === "" ? "" : root.tr("tag." + limitRow.situation.tag)
      color: limitRow.situation.color
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used, with an
  // optional even-pace benchmark tick (marker: elapsed window fraction,
  // -1 hides it).
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real marker: -1
    // Graduated consumption colors are opt-in per meter: the balance gauge
    // speaks remaining-fraction, not used-fraction, so it keeps the plain
    // foreground/urgent behavior.
    property bool graduated: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.graduated ? root.limitMeterColor(meter.value, meter.alarming)
                             : (meter.alarming ? root.urgent : root.foreground)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on color {
        ColorAnimation { duration: 160 }
      }
    }

    Rectangle {
      visible: meter.marker >= 0
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height + 4
      width: 2
      x: meterTrack.width * root.clamp(meter.marker, 0, 1) - width / 2
      radius: width / 2
      color: Color.accent
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
