#!/bin/bash
#
# Uninstall the opencode-go Omarchy plugin. Leaves usage history, popup state,
# and caches in place (they are your data); pass --purge to remove those too.
#
# Usage: ./uninstall.sh [--yes] [--purge]

set -euo pipefail

PLUGIN_ID="opencode-go"
ASSUME_YES=0
PURGE=0
for arg in "$@"; do
  case "$arg" in
  --yes | -y) ASSUME_YES=1 ;;
  --purge) PURGE=1 ;;
  *) echo "unknown option: $arg" >&2 && exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
confirm() {
  (( ASSUME_YES )) && return 0
  local answer=""
  read -r -p "$1 [y/N] " answer
  [[ $answer == [yY]* ]]
}

systemctl --user disable --now omarchy-agent-usage-opencode-go.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-agent-usage-opencode-go.service" \
  "$HOME/.config/systemd/user/omarchy-agent-usage-opencode-go.timer"
systemctl --user daemon-reload 2>/dev/null || true

rm -f "$HOME/.local/bin/omarchy-agent-usage-opencode-go" \
  "$HOME/.local/bin/omarchy-agent-usage-opencode-go-update"

rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

if (( PURGE )); then
  rm -f "$HOME/.local/state/omarchy/agents/usage/opencode-go.json" \
    "$HOME/.local/state/omarchy/agents/opencode-go-popup.json" \
    "$HOME/.local/state/omarchy/agents/opencode-go-history.jsonl"
  rm -f "$HOME/.cache/omarchy/agent-usage/opencode-go-"*.json
  say "Purged state, caches, and history."
else
  say "Kept state/history (pass --purge to remove)."
fi

if confirm "Re-enable the stock omarchy.agents panel?"; then
  omarchy plugin enable omarchy.agents --section right || true
fi

say "Uninstalled."
