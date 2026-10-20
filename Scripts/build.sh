#!/bin/bash
# Builds build/Melies.app (menu bar app, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/Melies.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Melies" "$APP/Contents/MacOS/Melies"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Icon
ICONSET=build/AppIcon.iconset
swift Scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (KeyboardShortcuts localizations)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

xattr -cr "$APP"

# Sign with a stable identity if one exists, so macOS keeps folder permissions between builds.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Signed ad hoc"
fi
echo "Built $APP"
