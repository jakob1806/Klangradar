#!/bin/zsh
# App-Store-Screenshots (iPhone 6,9" und iPad 13") mit echten Daten.
# Ergebnis: ios-native/AppStore/screenshots/<geraet>/*.png
# Erstellt von Claude Code.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/AppStore/screenshots"
SECRETS="$ROOT/Config/Secrets.plist"
[[ -f "$SECRETS" ]] || SECRETS="$HOME/Claude Projekte/ios-native/Config/Secrets.plist"
[[ -f "$SECRETS" ]] || { echo "Config/Secrets.plist fehlt (ohne echte Daten keine Screenshots)."; exit 1; }
if [[ ! -f "$ROOT/Config/Secrets.plist" ]]; then cp "$SECRETS" "$ROOT/Config/Secrets.plist"; (cd "$ROOT" && ruby Scripts/generate_project.rb >/dev/null); fi

udid_for() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)['devices']
for runtime in sorted((k for k in devices if 'iOS' in k), reverse=True):
    for d in devices[runtime]:
        if d['name'].startswith(name): print(d['udid']); sys.exit()
" "$1"
}

capture() {
  local label=$1 device=$2
  local udid=$(udid_for "$device")
  [[ -n "$udid" ]] || { echo "Kein Simulator '$device'"; return 1; }
  echo "▶ $label ($device)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName ""
  rm -rf "$OUT/$label"; mkdir -p "$OUT/$label"
  (cd "$ROOT" && TEST_RUNNER_SCREENSHOT_DIR="$OUT/$label" xcodebuild test \
      -project KlangradarNative.xcodeproj -scheme KlangradarNative \
      -destination "id=$udid" -only-testing:KlangradarNativeUITests/AppStoreScreenshots \
      -quiet 2>&1 | grep -E "error|Executed|passed|failed" | tail -5) || true
  xcrun simctl status_bar "$udid" clear || true
  ls "$OUT/$label"
}

capture iphone-6.9 "iPhone 16 Pro Max"
capture ipad-13 "iPad Pro 13-inch"
