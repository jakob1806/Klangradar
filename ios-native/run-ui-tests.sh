#!/bin/bash
# UI-Tests der nativen App im Simulator (feste Beispieldaten, kein Server).
set -euo pipefail
cd "$(dirname "$0")"
ruby Scripts/generate_project.rb >/dev/null
# iPhone-Simulator auf der neuesten installierten iOS-Version (per ID).
DEVICE_ID="${1:-$(xcrun simctl list devices available -j | python3 -c '
import json,sys,re
d=json.load(sys.stdin)["devices"]
runtimes=sorted((k for k in d if "iOS" in k), key=lambda k:[int(x) for x in re.findall(r"\d+",k.split("iOS")[-1])])
for rt in reversed(runtimes):
    phones=[x for x in d[rt] if x["name"].startswith("iPhone")]
    if phones: print(phones[0]["udid"]); break
')}"
xcodebuild test -project KlangradarNative.xcodeproj -scheme KlangradarNative \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -only-testing:KlangradarNativeUITests CODE_SIGNING_ALLOWED=NO > /tmp/klangradar-ui-tests.log 2>&1 \
  && { grep -E "Test Case.*passed" /tmp/klangradar-ui-tests.log | wc -l | xargs echo "✅ UI-Tests bestanden:"; } \
  || { grep -E "Test Case.*failed|error:" /tmp/klangradar-ui-tests.log | head -20; echo "❌ UI-Tests fehlgeschlagen (/tmp/klangradar-ui-tests.log)"; exit 1; }
