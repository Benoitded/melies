#!/bin/bash
# Builds a styled DMG: fixed-size window, background with an arrow, big icons, app next to Applications.
#   Scripts/make-dmg.sh <folder containing Melies.app> <output.dmg>
# Finder lays the window out through AppleScript, so the first run may ask to let the terminal control Finder.
# If that is refused, the DMG is still produced, just with the default plain layout.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$1"; OUT="$2"
VOL="Méliès"
TMP=$(mktemp -d); trap 'hdiutil detach "/Volumes/$VOL" -quiet -force 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkdir -p "$TMP/content/.background"
ditto --noextattr --noqtn "$SRC/Melies.app" "$TMP/content/Melies.app"
ln -s /Applications "$TMP/content/Applications"
# The small line under the window is for builds that are not notarized: set MELIES_DMG_HINT="" to hide it.
swift Scripts/dmg-background.swift "$TMP/content/.background/bg.png" "${MELIES_DMG_HINT-First launch: System Settings > Privacy & Security > Open Anyway}"

hdiutil create -quiet -volname "$VOL" -srcfolder "$TMP/content" -fs HFS+ -format UDRW -ov "$TMP/rw.dmg"
# Mounted normally (not -nobrowse): Finder must see the volume to lay its window out.
hdiutil attach -quiet -readwrite -noverify -noautoopen "$TMP/rw.dmg" -mountpoint "/Volumes/$VOL"
MNT="/Volumes/$VOL"

# A window of 660x400 points of content (468 with the title bar and the strip under it), app on the left, Applications on the right.
osascript <<OSA || echo "!! Finder layout skipped (automation not allowed): the DMG will use the default layout."
tell application "Finder"
  tell disk "$VOL"
  open
  set w to container window
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 860, 588}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 128
  set text size of o to 13
  set background picture of o to file ".background:bg.png"
  set position of item "Melies.app" to {180, 205}
  set position of item "Applications" to {480, 205}
  update without registering applications
  delay 3
  close w
  end tell
end tell
OSA
sync; sleep 1
chflags hidden "$MNT/.background" 2>/dev/null || true
hdiutil detach "$MNT" -quiet
rm -f "$OUT"
hdiutil convert -quiet "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Built $OUT"
