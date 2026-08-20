#!/bin/bash

PROJECT_DIR="/Users/jakob/Claude Projekte/ios-native"
SOURCE_DIR="$PROJECT_DIR/KlangradarNative"
DEPLOY_SCRIPT="$PROJECT_DIR/deploy-iphone.sh"

# Erst deployen, wenn so lange keine weitere Änderung kam
QUIET_TIME=10

# Wie oft nach Änderungen geschaut wird
CHECK_INTERVAL=2

cd "$PROJECT_DIR" || exit 1

clear

echo "╔══════════════════════════════════════════════╗"
echo "║        🎵 KLANGRADAR AUTO-DEPLOY            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "🟢 Auto-Deploy aktiv"
echo "📁 Überwacht: $SOURCE_DIR"
echo "⏱️  Deploy nach ${QUIET_TIME}s ohne weitere Änderung"
echo ""
echo "👀 Warte auf Codeänderungen …"
echo ""
echo "Beenden: Ctrl+C"
echo "────────────────────────────────────────────────"
echo ""

# -----------------------------------------------
# Aktuellen Zustand des Source Codes berechnen
# -----------------------------------------------

get_state() {

    find "$SOURCE_DIR" \
        -type f \
        \( \
            -name "*.swift" \
            -o -name "*.plist" \
            -o -name "*.json" \
            -o -name "*.strings" \
            -o -name "*.xcconfig" \
            -o -name "*.storyboard" \
            -o -name "*.xib" \
        \) \
        -exec stat -f "%m %N" {} \; \
        2>/dev/null \
        | sort \
        | shasum

}

LAST_STATE=$(get_state)

CHANGE_PENDING=false
LAST_CHANGE_TIME=0

while true
do

    sleep "$CHECK_INTERVAL"

    CURRENT_STATE=$(get_state)

    # -------------------------------------------
    # Änderung gefunden
    # -------------------------------------------

    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then

        NOW=$(date +%s)

        if [ "$CHANGE_PENDING" = false ]; then
            echo ""
            echo "$(date '+%H:%M:%S')  📝 Codeänderung erkannt."
            echo "$(date '+%H:%M:%S')  ⏳ Warte, bis Claude fertig ist …"
        else
            echo "$(date '+%H:%M:%S')  ↳ weitere Änderung erkannt – Timer zurückgesetzt"
        fi

        LAST_STATE="$CURRENT_STATE"
        LAST_CHANGE_TIME="$NOW"
        CHANGE_PENDING=true

        continue

    fi

    # -------------------------------------------
    # Es gibt ausstehende Änderungen
    # -------------------------------------------

    if [ "$CHANGE_PENDING" = true ]; then

        NOW=$(date +%s)
        ELAPSED=$((NOW - LAST_CHANGE_TIME))

        if [ "$ELAPSED" -ge "$QUIET_TIME" ]; then

            echo ""
            echo "$(date '+%H:%M:%S')  ✅ Seit ${QUIET_TIME}s keine Änderung mehr."
            echo "$(date '+%H:%M:%S')  🚀 Starte Auto-Deploy …"
            echo ""

            "$DEPLOY_SCRIPT"

            RESULT=$?

            echo ""

            if [ "$RESULT" -eq 0 ]; then
                echo "$(date '+%H:%M:%S')  🟢 Deploy erfolgreich."
            else
                echo "$(date '+%H:%M:%S')  🔴 Deploy fehlgeschlagen."
                echo "Fehlercode: $RESULT"
            fi

            CHANGE_PENDING=false

            # Zustand nach dem Build erneut erfassen
            LAST_STATE=$(get_state)

            echo ""
            echo "────────────────────────────────────────────────"
            echo "$(date '+%H:%M:%S')  👀 Warte auf nächste Codeänderung …"
            echo ""

        fi

    fi

done

