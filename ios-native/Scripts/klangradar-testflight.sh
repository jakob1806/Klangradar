#!/bin/bash
# Lädt Klangradar aus einem frischen origin/main-Checkout zu TestFlight hoch.
# Installiert als ~/bin/klangradar-testflight (Scripts/install-testflight-watch.sh).
# Ergänzt von Claude Code (27.10.2026): Sperre gegen parallele Uploads und
# Merken des hochgeladenen Commits, damit der Wächter (testflight-watch.sh)
# denselben Stand nicht noch einmal hochlädt.
set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
REPO="/Users/jakob/Claude Projekte"
WT="$HOME/.klangradar-testflight-wt"
LOCK="/tmp/klangradar-testflight.lock"
mkdir "$LOCK" 2>/dev/null || { echo "❌ Es läuft bereits ein TestFlight-Upload ($LOCK)."; exit 1; }
trap 'rmdir "$LOCK"' EXIT

git -C "$REPO" fetch -q origin main
git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT"; git -C "$REPO" worktree prune
git -C "$REPO" worktree add -q --detach "$WT" origin/main
SHA=$(git -C "$WT" rev-parse HEAD)
echo "Stand: $(git -C "$WT" log --oneline -1)"
cp "$REPO/ios-native/Config/Secrets.plist" "$WT/ios-native/Config/Secrets.plist"
cd "$WT/ios-native"
ruby Scripts/generate_project.rb >/dev/null
./upload-testflight.sh
echo "$SHA" > "$HOME/.klangradar-testflight-last-sha"
