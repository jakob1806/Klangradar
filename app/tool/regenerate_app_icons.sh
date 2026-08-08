#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
master="${1:-$app_root/design/app-icon/klassik-muenchen-app-icon-master-1024.png}"

if [[ ! -f "$master" ]]; then
  echo "Master icon not found: $master" >&2
  exit 1
fi

resize() {
  local size="$1"
  local target="$2"
  sips --resampleHeightWidth "$size" "$size" "$master" --out "$target" >/dev/null
}

ios="$app_root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
resize 40 "$ios/Icon-App-20x20@2x.png"
resize 60 "$ios/Icon-App-20x20@3x.png"
resize 29 "$ios/Icon-App-29x29@1x.png"
resize 58 "$ios/Icon-App-29x29@2x.png"
resize 87 "$ios/Icon-App-29x29@3x.png"
resize 40 "$ios/Icon-App-40x40@1x.png"
resize 80 "$ios/Icon-App-40x40@2x.png"
resize 120 "$ios/Icon-App-40x40@3x.png"
resize 120 "$ios/Icon-App-60x60@2x.png"
resize 180 "$ios/Icon-App-60x60@3x.png"
resize 20 "$ios/Icon-App-20x20@1x.png"
resize 76 "$ios/Icon-App-76x76@1x.png"
resize 152 "$ios/Icon-App-76x76@2x.png"
resize 167 "$ios/Icon-App-83.5x83.5@2x.png"
resize 1024 "$ios/Icon-App-1024x1024@1x.png"

android="$app_root/android/app/src/main/res"
resize 48 "$android/mipmap-mdpi/ic_launcher.png"
resize 72 "$android/mipmap-hdpi/ic_launcher.png"
resize 96 "$android/mipmap-xhdpi/ic_launcher.png"
resize 144 "$android/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$android/mipmap-xxxhdpi/ic_launcher.png"

web="$app_root/web"
resize 32 "$web/favicon.png"
resize 192 "$web/icons/Icon-192.png"
resize 512 "$web/icons/Icon-512.png"
resize 192 "$web/icons/Icon-maskable-192.png"
resize 512 "$web/icons/Icon-maskable-512.png"

echo "App icons regenerated from $master"
