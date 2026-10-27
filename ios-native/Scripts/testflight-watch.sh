#!/bin/bash
# Erstellt von Claude Code (Nutzerwunsch 27.10.2026): startet den TestFlight-
# Upload automatisch, sobald ein gemergter Stand auf main
#   1. die iOS-App betrifft (Änderungen unter ios-native/),
#   2. alle GitHub-Läufe für diesen Commit abgeschlossen hat – inklusive der
#      freigabepflichtigen Deploys (Migrationen, Edge Functions) – und
#   3. keiner davon fehlgeschlagen ist.
# Wartet ein Deploy auf Freigabe oder schlägt etwas fehl, kommt eine
# macOS-Mitteilung statt eines Uploads.
#
# Läuft alle 5 Minuten per launchd (Scripts/install-testflight-watch.sh).
# Zustand:  ~/.klangradar-testflight-last-sha  (zuletzt hochgeladener Commit,
#           schreibt auch ~/bin/klangradar-testflight bei manuellen Uploads)
# Log:      ~/Library/Logs/klangradar-testflight-watch.log
# Test:     DRY_RUN=1 Scripts/testflight-watch.sh  (prüft nur, lädt nichts hoch)
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="jakob1806/Klangradar"
STATE="$HOME/.klangradar-testflight-last-sha"
NOTIFIED="$HOME/.klangradar-testflight-notified"   # "<sha> <grund>" – je Grund nur einmal melden
ATTEMPTS="$HOME/.klangradar-testflight-attempts"   # "<sha> <anzahl>"
LOCK="/tmp/klangradar-testflight.lock"
UPLOAD="$HOME/bin/klangradar-testflight"
MAX_ATTEMPTS=3

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
notify() {
  osascript -e "display notification \"$2\" with title \"Klangradar TestFlight\" subtitle \"$1\"" >/dev/null 2>&1 || true
}
notify_once() { # sha grund titel text
  grep -qx "$1 $2" "$NOTIFIED" 2>/dev/null && return
  echo "$1 $2" >> "$NOTIFIED"
  notify "$3" "$4"
}

[ -d "$LOCK" ] && { log "Upload läuft bereits – übersprungen"; exit 0; }

SHA=$(gh api "repos/$REPO/commits/main" -q .sha 2>/dev/null) || { log "GitHub nicht erreichbar"; exit 0; }
LAST=$(cat "$STATE" 2>/dev/null || true)
[ "$SHA" = "$LAST" ] && exit 0
SHORT=${SHA:0:7}
TITLE=$(gh api "repos/$REPO/commits/$SHA" -q '.commit.message | split("\n")[0]' 2>/dev/null | cut -c1-80)

# Betrifft der neue Stand die iOS-App? Sonst nur merken, kein Upload.
# Doku (*.md) und die Upload-Skripte selbst zählen nicht als App-Änderung.
if [ -n "$LAST" ]; then
  IOS_CHANGES=$(gh api "repos/$REPO/compare/$LAST...$SHA" -q '[.files[].filename | select(startswith("ios-native/")) | select((test("\\.md$") or test("^ios-native/Scripts/(testflight-watch|install-testflight-watch|klangradar-testflight)\\.sh$")) | not)] | length' 2>/dev/null || echo "?")
  if [ "$IOS_CHANGES" = "0" ]; then
    log "$SHORT ohne iOS-Änderungen – kein Upload nötig"
    [ "${DRY_RUN:-0}" = "1" ] || echo "$SHA" > "$STATE"
    exit 0
  fi
fi

RUNS=$(gh run list --repo "$REPO" --commit "$SHA" --limit 50 --json name,status,conclusion 2>/dev/null) || { log "Läufe nicht abrufbar"; exit 0; }
if [ "$(echo "$RUNS" | jq 'map(select(.name == "iOS CI")) | length')" = "0" ]; then
  log "$SHORT: iOS CI noch nicht gestartet – warte"
  exit 0
fi

WAITING=$(echo "$RUNS" | jq -r 'map(select(.status == "waiting")) | map(.name) | join(", ")')
if [ -n "$WAITING" ]; then
  log "$SHORT wartet auf Freigabe: $WAITING"
  [ "${DRY_RUN:-0}" = "1" ] || notify_once "$SHA" waiting "Freigabe ausstehend" "$WAITING – danach startet der Upload automatisch."
  exit 0
fi
OPEN=$(echo "$RUNS" | jq -r 'map(select(.status != "completed")) | map(.name) | join(", ")')
if [ -n "$OPEN" ]; then
  log "$SHORT läuft noch: $OPEN"
  exit 0
fi
FAILED=$(echo "$RUNS" | jq -r 'map(select(.conclusion as $c | ["success","skipped","neutral"] | index($c) | not)) | map(.name + " (" + .conclusion + ")") | join(", ")')
if [ -n "$FAILED" ]; then
  log "$SHORT fehlgeschlagen: $FAILED"
  [ "${DRY_RUN:-0}" = "1" ] || notify_once "$SHA" failed "Kein Upload – Check fehlgeschlagen" "$FAILED"
  exit 0
fi

[ "${DRY_RUN:-0}" = "1" ] && { log "$SHORT alles grün – würde jetzt hochladen (DRY_RUN): $TITLE"; exit 0; }
COUNT=$(awk -v s="$SHA" '$1==s {print $2}' "$ATTEMPTS" 2>/dev/null)
COUNT=${COUNT:-0}
if [ "$COUNT" -ge "$MAX_ATTEMPTS" ]; then
  notify_once "$SHA" gaveup "Upload aufgegeben" "$MAX_ATTEMPTS Versuche für $SHORT fehlgeschlagen – bitte Log prüfen."
  exit 0
fi
{ grep -v "^$SHA " "$ATTEMPTS" 2>/dev/null; echo "$SHA $((COUNT + 1))"; } > "$ATTEMPTS.tmp" && mv "$ATTEMPTS.tmp" "$ATTEMPTS"

log "$SHORT alles grün – starte TestFlight-Upload (Versuch $((COUNT + 1))): $TITLE"
notify "Upload startet" "$TITLE"
OUTPUT=$("$UPLOAD" 2>&1)
STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
BUILD=$(echo "$OUTPUT" | grep -o 'Version [0-9.]* (Build [0-9]*)' | tail -1)
if [ $STATUS -eq 0 ] && [ -n "$BUILD" ]; then
  log "$SHORT hochgeladen: $BUILD"
  notify "Hochgeladen: $BUILD" "$TITLE – in 10–30 Min. in TestFlight."
else
  REASON=$(echo "$OUTPUT" | grep '❌' | tail -1)
  log "$SHORT Upload fehlgeschlagen: ${REASON:-Status $STATUS}"
  notify "Upload fehlgeschlagen" "${REASON:-Status $STATUS} – nächster Versuch in 5 Min."
fi
