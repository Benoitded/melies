#!/bin/bash
# Builds build.noindex/Melies.app (menu bar app, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build.noindex/Melies.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Melies" "$APP/Contents/MacOS/Melies"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Icon
ICONSET=build.noindex/AppIcon.iconset
swift Scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Localizations (en, fr, it, es)
cp -R Localization/*.lproj "$APP/Contents/Resources/"

# SwiftPM resource bundles (KeyboardShortcuts localizations)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# Sign with a stable identity if one exists, so macOS keeps folder and screen permissions between builds.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
SIGN_AS="${IDENTITY:--}"

# codesign sometimes trips on stray Finder attributes; clear them and retry before failing loudly.
sign() {
  for _ in 1 2 3; do
    xattr -cr "$APP"
    xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
    codesign --force --deep --sign "$SIGN_AS" "$APP" 2>/dev/null && return 0
    sleep 1
  done
  codesign --force --deep --sign "$SIGN_AS" "$APP"
}
sign
codesign --verify --deep --strict "$APP"
echo "Signed with: ${IDENTITY:-ad hoc}"

# One installed copy only: ~/Applications/Melies.app (the build dir is ignored by Spotlight).
pkill -x Melies 2>/dev/null || true
rm -rf "$HOME/Applications/Melies.app"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$HOME/Applications/Melies.app"
echo "Installed ~/Applications/Melies.app"
