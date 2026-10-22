#!/bin/bash
# Builds Méliès, signs it, and installs the single copy at ~/Applications/Melies.app.
# The bundle is assembled and signed in a temp dir, away from Spotlight and Finder, which
# otherwise race with codesign by writing stray attributes into the bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/melies-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Melies.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp -X "$BIN/Melies" "$APP/Contents/MacOS/Melies"
cp -X Scripts/Info.plist "$APP/Contents/Info.plist"

# Liquid Glass icon: the layered Resources/Melies.icon becomes Assets.car (+ a flat fallback .icns).
xcrun actool Resources/Melies.icon --compile "$APP/Contents/Resources" \
  --platform macosx --target-device mac --minimum-deployment-target 26.0 \
  --app-icon Melies --include-all-app-icons \
  --output-partial-info-plist "$STAGE/icon-partial.plist" > /dev/null

# Localizations (en, fr, it, es)
cp -RX Localization/*.lproj "$APP/Contents/Resources/"

# SwiftPM resource bundles (KeyboardShortcuts localizations)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -RX "$b" "$APP/Contents/Resources/"; done

# Sign with a stable identity if one exists, so macOS keeps folder and screen permissions between builds.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
SIGN_AS="${IDENTITY:--}"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign "$SIGN_AS" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed with: ${IDENTITY:-ad hoc}"

# One installed copy only. ditto keeps the signature and drops extended attributes.
pkill -x Melies 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Melies.app"
ditto --noextattr --noqtn "$APP" "$HOME/Applications/Melies.app"
codesign --verify --deep --strict "$HOME/Applications/Melies.app"
echo "Installed ~/Applications/Melies.app"
