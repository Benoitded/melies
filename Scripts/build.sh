#!/bin/bash
# Builds Méliès, signs it, and installs the single copy at ~/Applications/Melies.app.
# Used as is for daily work. Scripts/release.sh drives it with:
#   MELIES_SIGN_IDENTITY  signing identity (default: the first "Apple Development", else ad hoc)
#   MELIES_HARDENED=1     hardened runtime + secure timestamp (needed for notarization)
#   MELIES_OUT=dir        leave Melies.app in dir and do not install or quit the running app
# The bundle is assembled and signed in a temp dir, away from Spotlight and Finder, which
# otherwise race with codesign by writing stray attributes into the bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftUI macros (@State, #Preview...) ship with Xcode.app, not with the Command Line Tools: building with the
# tools alone fails with "plugin for module 'SwiftUIMacros' not found". Use Xcode when it is installed.
case "$(xcode-select -p 2>/dev/null)" in
  *.app/Contents/Developer) ;;
  *)
    # "|| true": with pipefail, no Xcode makes ls fail and set -e would exit silently, before the help below.
    XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1 || true)
    if [ -n "$XCODE" ]; then
      export DEVELOPER_DIR="$XCODE/Contents/Developer"
      echo "Using $XCODE (xcode-select points to the Command Line Tools)."
    else
      echo "Méliès needs Xcode 26 or later (the full app, not only the Command Line Tools)."
      echo "  1. Install Xcode from the App Store or https://developer.apple.com/xcode/"
      echo "  2. Open it once and accept the license, then run:"
      echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
      exit 1
    fi
    ;;
esac

swift build -c release --force-resolved-package-versions
BIN=$(swift build -c release --force-resolved-package-versions --show-bin-path)

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

# Sparkle (automatic updates): the framework lives next to the executable's Frameworks folder.
mkdir -p "$APP/Contents/Frameworks"
cp -RX "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Melies" 2>/dev/null || true
# Without this path the app cannot find Sparkle and crashes at launch: fail here, not on the user's Mac.
otool -l "$APP/Contents/MacOS/Melies" | grep -q "@executable_path/../Frameworks" \
  || { echo "Sparkle search path missing in the executable."; exit 1; }

# SwiftPM resource bundles (KeyboardShortcuts localizations)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -RX "$b" "$APP/Contents/Resources/"; done

# Sign with a stable identity if one exists, so macOS keeps folder and screen permissions between builds.
IDENTITY="${MELIES_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)}"
SIGN_AS="${IDENTITY:--}"
FLAGS=(--force --sign "$SIGN_AS")
[ "${MELIES_HARDENED:-0}" = "1" ] && FLAGS+=(--options runtime --timestamp)
xattr -cr "$APP" 2>/dev/null || true
# Inside out: Sparkle's helpers first, then the framework, then the app (--deep would not sign them in this order).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/XPCServices/Downloader.xpc" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  [ -e "$part" ] && codesign "${FLAGS[@]}" "$part"
done
codesign "${FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
# The app gets the entitlements (microphone, needed once the hardened runtime is on); Sparkle's parts keep none.
codesign "${FLAGS[@]}" --entitlements Scripts/Melies.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed with: ${MELIES_SIGN_NAME:-${IDENTITY:-ad hoc}}"

if [ -n "${MELIES_OUT:-}" ]; then
  rm -rf "$MELIES_OUT/Melies.app"; mkdir -p "$MELIES_OUT"
  ditto --noextattr --noqtn "$APP" "$MELIES_OUT/Melies.app"
  echo "Built $MELIES_OUT/Melies.app"
  exit 0
fi

# One installed copy only. ditto keeps the signature and drops extended attributes.
pkill -x Melies 2>/dev/null || true
mkdir -p "$HOME/Applications"
# Copy beside, check, then swap: a failed copy never leaves the Mac without the app.
rm -rf "$HOME/Applications/.Melies-new.app"
ditto --noextattr --noqtn "$APP" "$HOME/Applications/.Melies-new.app"
codesign --verify --deep --strict "$HOME/Applications/.Melies-new.app"
rm -rf "$HOME/Applications/Melies.app"
mv "$HOME/Applications/.Melies-new.app" "$HOME/Applications/Melies.app"
echo "Installed ~/Applications/Melies.app"
