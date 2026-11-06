#!/bin/sh
# Erstellt von Claude Code (06.11.2026): Xcode Cloud führt dieses Skript nach
# dem Klonen aus. Config/Secrets.plist ist nicht im Repo; sie entsteht hier aus
# den Umgebungsvariablen des Xcode-Cloud-Workflows SUPABASE_URL und
# SUPABASE_ANON_KEY (in App Store Connect → Xcode Cloud → Workflow →
# Environment hinterlegen, den Schlüssel als „Secret“ markieren).
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/ios-native"
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "error: SUPABASE_URL / SUPABASE_ANON_KEY fehlen im Xcode-Cloud-Workflow." >&2
  exit 1
fi
cat > Config/Secrets.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>${SUPABASE_URL}</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>${SUPABASE_ANON_KEY}</string>
</dict>
</plist>
PLIST
echo "Secrets.plist erstellt."

# Die Datei muss auch ins App-Paket: Das eingecheckte Xcode-Projekt kennt sie
# nicht (sie ist nicht im Repo). Wie beim lokalen Upload das Projekt neu
# erzeugen – generate_project.rb nimmt Secrets.plist auf, wenn sie existiert.
# (06.11.2026: Build 1.0 (3) startete sonst ohne Supabase-Konfiguration.)
gem install --user-install --no-document xcodeproj -v 1.28.1
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
export GEM_PATH="$(ruby -e 'print Gem.user_dir'):${GEM_PATH:-}"
ruby Scripts/generate_project.rb
grep -q "Secrets.plist" KlangradarNative.xcodeproj/project.pbxproj || { echo "error: Secrets.plist nicht im Projekt" >&2; exit 1; }
echo "Projekt mit Secrets.plist neu erzeugt."
