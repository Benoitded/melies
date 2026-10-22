#!/bin/bash
# Builds a styled DMG: fixed-size window, background with an arrow, big icons, app next to Applications.
#   Scripts/make-dmg.sh <folder containing Melies.app> <output.dmg>
# Finder lays the window out through AppleScript, so the first run may ask to let the terminal control Finder.
# If that is refused, the DMG is still produced, just with the default plain layout.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$1"; OUT="$2"
VOL="Méliès"
TMP=$(mktemp -d); trap 'hdiutil detach "$TMP/mnt" -quiet -force 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkdir -p "$TMP/content/.background"
ditto --noextattr --noqtn "$SRC/Melies.app" "$TMP/content/Melies.app"
ln -s /Applications "$TMP/content/Applications"
# MELIES_DMG_HINT="First launch: right-click the app, then Open" adds a small line (for builds that are not notarized).
swift Scripts/dmg-background.swift "$TMP/content/.background/bg.png" "${MELIES_DMG_HINT:-}"

hdiutil create -quiet -volname "$VOL" -srcfolder "$TMP/content" -fs HFS+ -format UDRW -ov "$TMP/rw.dmg"
mkdir "$TMP/mnt"
hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse -mountpoint "$TMP/mnt" "$TMP/rw.dmg"

# A window of 660x400 points (428 with the title bar), app on the left, Applications on the right.
osascript <<OSA || echo "!! Finder layout skipped (automation not allowed): the DMG will use the default layout."
tell application "Finder"
  set d to POSIX file "$TMP/mnt" as alias
  open d
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 860, 548}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 128
  set text size of o to 13
  set background picture of o to (POSIX file "$TMP/mnt/.background/bg.png" as alias)
  set position of item "Melies.app" of d to {180, 190}
  set position of item "Applications" of d to {480, 190}
  update d without registering applications
  delay 1
  close w
end tell
OSA
sync; sleep 1
chflags hidden "$TMP/mnt/.background" 2>/dev/null || true
hdiutil detach "$TMP/mnt" -quiet
rm -f "$OUT"
hdiutil convert -quiet "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Built $OUT"
