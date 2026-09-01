#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT="KlangradarNative.xcodeproj"
SCHEME="KlangradarNative"

DEVICE_ID="D0A148F1-00E3-56A9-97FD-C930EFD767DC"
DEVICE_NAME="iPhone von Jakob"

BUNDLE_ID="de.klangradar.native"

DERIVED_DATA="/tmp/KlangradarNativeDerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/KlangradarNative.app"
SOURCE_SECRETS="$PROJECT_DIR/Config/Secrets.plist"

cd "$PROJECT_DIR"

timestamp() {
    date "+%H:%M:%S"
}

log() {
    echo "$(timestamp)  $1"
}

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🚀 Neuer Klangradar-Deploy"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ------------------------------------------
# Supabase-Konfiguration vorab prüfen
# ------------------------------------------

log "🔐 Prüfe Supabase-Konfiguration …"

if [ ! -f "$SOURCE_SECRETS" ]; then
    log "❌ Config/Secrets.plist fehlt. Es wird keine Demo-App gebaut."
    exit 8
fi

if ! plutil -lint "$SOURCE_SECRETS" >/dev/null 2>&1; then
    log "❌ Config/Secrets.plist ist ungültig."
    exit 8
fi

SUPABASE_URL_VALUE=$(plutil -extract SUPABASE_URL raw "$SOURCE_SECRETS" 2>/dev/null)
SUPABASE_KEY_VALUE=$(plutil -extract SUPABASE_ANON_KEY raw "$SOURCE_SECRETS" 2>/dev/null)

if [[ "$SUPABASE_URL_VALUE" != https://* ]] || [ -z "$SUPABASE_KEY_VALUE" ]; then
    log "❌ Supabase-URL oder Anon-Key fehlt. Es wird keine Demo-App gebaut."
    exit 8
fi

log "✅ Supabase-Konfiguration vorhanden."

echo ""

# ------------------------------------------
# iPhone prüfen
# ------------------------------------------

log "🔎 Suche $DEVICE_NAME …"

DEVICE_LIST=$(xcrun devicectl list devices 2>&1)

if ! echo "$DEVICE_LIST" | grep -q "$DEVICE_ID"; then
    log "❌ iPhone nicht gefunden."
    echo ""
    log "   → Ist das iPhone eingeschaltet?"
    log "   → Sind Mac und iPhone verbunden?"
    log "   → Funktioniert Wireless Debugging?"
    echo ""
    exit 2
fi

if ! echo "$DEVICE_LIST" | grep "$DEVICE_ID" | grep -q "connected"; then
    log "⚠️ iPhone gefunden, aber nicht verbunden."
    echo ""
    log "   → iPhone entsperren."
    log "   → WLAN/Bluetooth-Verbindung prüfen."
    echo ""
    exit 3
fi

log "✅ $DEVICE_NAME ist verbunden."

echo ""

# ------------------------------------------
# BUILD
# ------------------------------------------

log "🔨 Build wird gestartet …"
echo ""

BUILD_LOG="/tmp/klangradar-build.log"

xcodebuild \
-project "$PROJECT" \
-scheme "$SCHEME" \
-configuration Debug \
-destination "id=$DEVICE_ID" \
-derivedDataPath "$DERIVED_DATA" \
-allowProvisioningUpdates \
build >"$BUILD_LOG" 2>&1

BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then

    log "❌ BUILD FEHLGESCHLAGEN"
    echo ""
    log "Die letzten Meldungen von Xcode:"
    echo ""
    
    tail -40 "$BUILD_LOG"

    echo ""
    log "→ Code bzw. Xcode-Fehler beheben."
    echo ""

    exit 4
fi

log "✅ Build erfolgreich."

# ------------------------------------------
# APP prüfen
# ------------------------------------------

if [ ! -d "$APP_PATH" ]; then

    log "❌ Gebaute App wurde nicht gefunden."
    log "Pfad: $APP_PATH"

    exit 5
fi

# Niemals einen Build installieren, der wegen fehlender Secrets in die
# Preview-Repositories von AppEnvironment zurückfallen würde.
EMBEDDED_SECRETS="$APP_PATH/Secrets.plist"
if [ ! -f "$EMBEDDED_SECRETS" ]; then
    log "❌ Build enthält keine Supabase-Konfiguration und wird nicht installiert."
    exit 8
fi

EMBEDDED_URL=$(plutil -extract SUPABASE_URL raw "$EMBEDDED_SECRETS" 2>/dev/null)
EMBEDDED_KEY=$(plutil -extract SUPABASE_ANON_KEY raw "$EMBEDDED_SECRETS" 2>/dev/null)

if [ "$EMBEDDED_URL" != "$SUPABASE_URL_VALUE" ] || [ "$EMBEDDED_KEY" != "$SUPABASE_KEY_VALUE" ]; then
    log "❌ Eingebettete Supabase-Konfiguration stimmt nicht mit Config/Secrets.plist überein."
    exit 8
fi

log "✅ Native App enthält die korrekte Supabase-Anbindung."

echo ""

# ------------------------------------------
# INSTALL
# ------------------------------------------

log "📲 Installiere Klangradar auf dem iPhone …"

INSTALL_OUTPUT=$(xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$APP_PATH" 2>&1)

INSTALL_STATUS=$?

if [ $INSTALL_STATUS -ne 0 ]; then

    echo ""
    log "❌ Installation fehlgeschlagen."
    echo ""

    echo "$INSTALL_OUTPUT"

    echo ""

    if echo "$INSTALL_OUTPUT" | grep -qiE "locked|unlock|passcode"; then

        log "🔒 Das iPhone scheint gesperrt zu sein."
        log "→ Bitte iPhone entsperren."

    else

        log "→ Verbindung und iPhone prüfen."

    fi

    echo ""

    exit 6
fi

log "✅ Installation erfolgreich."

echo ""

# ------------------------------------------
# START
# ------------------------------------------

log "🚀 Starte Klangradar …"

LAUNCH_OUTPUT=$(xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    "$BUNDLE_ID" 2>&1)

LAUNCH_STATUS=$?

if [ $LAUNCH_STATUS -ne 0 ]; then

    echo ""
    log "❌ App konnte nicht gestartet werden."
    echo ""

    echo "$LAUNCH_OUTPUT"

    echo ""

    if echo "$LAUNCH_OUTPUT" | grep -qiE "locked|unlock|passcode"; then

        log "🔒 iPhone entsperren und erneut versuchen."
    fi

    echo ""

    exit 7
fi

log "✅ Klangradar wurde gestartet."

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "✅ DEPLOY ABGESCHLOSSEN"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
