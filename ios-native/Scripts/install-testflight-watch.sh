#!/bin/bash
# Erstellt von Claude Code (27.10.2026): installiert den automatischen
# TestFlight-Upload nach Merge + Deploy-Freigabe (testflight-watch.sh) als
# launchd-Agent (alle 5 Minuten) und aktualisiert ~/bin/klangradar-testflight.
# Deinstallieren: launchctl bootout gui/$(id -u)/de.klangradar.testflight-watch
#                 && rm ~/Library/LaunchAgents/de.klangradar.testflight-watch.plist
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="de.klangradar.testflight-watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 755 "$DIR/klangradar-testflight.sh" "$HOME/bin/klangradar-testflight"
install -m 755 "$DIR/testflight-watch.sh" "$HOME/bin/klangradar-testflight-watch"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$HOME/bin/klangradar-testflight-watch</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/klangradar-testflight-watch.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/klangradar-testflight-watch.log</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "✅ TestFlight-Wächter aktiv (alle 5 Min.), Log: ~/Library/Logs/klangradar-testflight-watch.log"
