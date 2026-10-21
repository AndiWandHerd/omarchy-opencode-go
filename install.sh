#!/bin/bash
#
# Install the opencode-go Omarchy plugin: shell plugin, quota collector,
# systemd timer, and bar placement. Idempotent — safe to re-run for updates.
#
# Usage: ./install.sh [--yes]
#   --yes / -y  Answer yes to all prompts (non-interactive).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="opencode-go"
ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1

say() { printf '%s\n' "$*"; }
confirm() {
  (( ASSUME_YES )) && return 0
  local answer=""
  read -r -p "$1 [y/N] " answer
  [[ $answer == [yY]* ]]
}

command -v omarchy >/dev/null 2>&1 || {
  echo "error: omarchy CLI not found — install this on Omarchy." >&2
  exit 1
}

say "1/5 validating plugin…"
omarchy plugin validate "$REPO_DIR"

say "2/5 installing plugin files…"
mkdir -p "$HOME/.config/omarchy/plugins"
rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
cp -a "$REPO_DIR" "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
# Strip development-only files from the installed copy.
rm -rf \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/.git" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/collectors" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/systemd" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/docs" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/install.sh" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/uninstall.sh" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/.gitignore" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/CHANGELOG.md" \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/CONTRIBUTING.md"

say "3/5 installing collector + systemd units…"
mkdir -p "$HOME/.local/bin"
install -m 0755 "$REPO_DIR/collectors/omarchy-agent-usage-opencode-go" "$HOME/.local/bin/"
install -m 0755 "$REPO_DIR/collectors/omarchy-agent-usage-opencode-go-update" "$HOME/.local/bin/"
mkdir -p "$HOME/.config/systemd/user"
install -m 0644 "$REPO_DIR/systemd/omarchy-agent-usage-opencode-go.service" "$HOME/.config/systemd/user/"
install -m 0644 "$REPO_DIR/systemd/omarchy-agent-usage-opencode-go.timer" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-opencode-go.timer

say "4/5 enabling bar widget…"
omarchy-shell shell rescanPlugins >/dev/null
if jq -e --arg id "$PLUGIN_ID" '.bar.layout | .. | objects | select(has("id")) | select(.id == $id)' \
  "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  say "  already in the bar layout, keeping placement"
else
  omarchy plugin enable "$PLUGIN_ID" --section right
fi

say "5/5 stock agents panel…"
say "  This plugin replaces the stock omarchy.agents panel (same providers, more features)."
if confirm "  Disable the stock omarchy.agents panel to avoid a duplicate icon?"; then
  omarchy plugin disable omarchy.agents || true
fi

say "Done. First data lands within ~5 minutes (or run omarchy-agent-usage-opencode-go-update now)."
say "If QML changes do not appear, apply them with: omarchy restart shell"
