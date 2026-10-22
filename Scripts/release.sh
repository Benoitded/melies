#!/bin/bash
# Publishes a new Méliès version in one command:
#   Scripts/release.sh            bump the patch number (0.1.0 -> 0.1.1)
#   Scripts/release.sh minor      0.1.1 -> 0.2.0       (also: major)
#   Scripts/release.sh 1.4.0      an exact version
#   Scripts/release.sh --dry-run  build, DMG and appcast in dist/, without touching git or GitHub
#   --allow-unnotarized           publish even if notarization did not happen (for tests only)
#   --skip-notarization           do not submit to Apple (fast pre-release builds: Gatekeeper will warn)
#
# What it does: bumps the version, builds and signs the app (Developer ID + hardened runtime when that
# certificate exists), makes the DMG, notarizes and staples it (when the "melies-notary" profile exists),
# signs the update for Sparkle, writes appcast.xml, commits and tags, then creates the GitHub release with
# the DMG and appcast.xml. Installed apps find appcast.xml at releases/latest/download (SUFeedURL).
#
# One-time setup, see docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; ARG=patch; ALLOW_UNNOTARIZED=0; SKIP_NOTARIZATION=0
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --allow-unnotarized) ALLOW_UNNOTARIZED=1 ;; --skip-notarization) SKIP_NOTARIZATION=1 ;; *) ARG="$a" ;; esac; done

PLIST=Scripts/Info.plist
PB=/usr/libexec/PlistBuddy
CURRENT=$($PB -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$($PB -c "Print :CFBundleVersion" "$PLIST")
IFS=. read -r MA MI PA <<<"$CURRENT"
case "$ARG" in
  patch) VERSION="$MA.$MI.$((PA + 1))" ;;
  minor) VERSION="$MA.$((MI + 1)).0" ;;
  major) VERSION="$((MA + 1)).0.0" ;;
  [0-9]*.[0-9]*.[0-9]*) VERSION="$ARG" ;;
  *) echo "Usage: $0 [patch|minor|major|X.Y.Z] [--dry-run]"; exit 1 ;;
esac
NEXT_BUILD=$((BUILD + 1))
TAG="v$VERSION"
echo "==> Méliès $CURRENT ($BUILD) -> $VERSION ($NEXT_BUILD)"

if [ "$DRY" = 0 ]; then
  [ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "Release from main (git checkout main && git pull)."; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh is not logged in (gh auth login)."; exit 1; }
  git rev-parse "$TAG" >/dev/null 2>&1 && { echo "Tag $TAG already exists."; exit 1; }
fi

# Release notes: the commit subjects since the previous tag.
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
RANGE=${LAST_TAG:+$LAST_TAG..HEAD}
DIST=dist; rm -rf "$DIST"; mkdir -p "$DIST/updates"
{ git log ${RANGE:-} --no-merges --pretty='- %s' | grep -v "^- Merge" || true; } > "$DIST/updates/Melies-$VERSION.md"
[ -s "$DIST/updates/Melies-$VERSION.md" ] || echo "- Improvements and fixes" > "$DIST/updates/Melies-$VERSION.md"

# Version bump (restored if anything fails before the commit).
cp "$PLIST" "$DIST/Info.plist.bak"
trap 'cp "$DIST/Info.plist.bak" "$PLIST" 2>/dev/null || true' ERR
$PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
$PB -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"

# Signing: Developer ID if available, else the development certificate (fine to test, not to distribute).
# Identified by its SHA-1 hash: names with accents (Benoît) get mangled when copied through the shell.
DEVID=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | awk '{print $2}' || true)
DEVID_NAME=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/' || true)
if [ -n "$DEVID" ]; then
  echo "==> Signing with: $DEVID_NAME (hardened runtime)"
  MELIES_SIGN_IDENTITY="$DEVID" MELIES_SIGN_NAME="$DEVID_NAME" MELIES_HARDENED=1 MELIES_OUT="$DIST/stage" Scripts/build.sh
else
  echo "!! No \"Developer ID Application\" certificate: this build will not pass Gatekeeper on other Macs."
  MELIES_OUT="$DIST/stage" Scripts/build.sh
fi

# DMG: the app next to an Applications shortcut.
DMG="$DIST/updates/Melies-$VERSION.dmg"
ln -s /Applications "$DIST/stage/Applications"
hdiutil create -quiet -volname "Méliès" -srcfolder "$DIST/stage" -format UDZO -ov "$DMG"
[ -n "$DEVID" ] && codesign --force --sign "$DEVID" --timestamp "$DMG"

NOTARIZED=0
# Notarization, when the keychain profile exists (xcrun notarytool store-credentials melies-notary).
if [ "$SKIP_NOTARIZATION" = 1 ]; then
  echo "!! Skipping notarization as asked."
elif [ -n "$DEVID" ] && xcrun notarytool history --keychain-profile melies-notary >/dev/null 2>&1; then
  echo "==> Notarizing (a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile melies-notary --wait
  xcrun stapler staple "$DMG"
  NOTARIZED=1
else
  echo "!! Not notarized (missing certificate or the melies-notary profile)."
fi

# Sparkle: sign the archive and write the appcast (the private key is in your keychain).
TOOLS=.build/artifacts/sparkle/Sparkle/bin
"$TOOLS/generate_appcast" "$DIST/updates" \
  --download-url-prefix "https://github.com/Benoitded/melies/releases/download/$TAG/" \
  --embed-release-notes -o "$DIST/appcast.xml"
echo "==> Built $DMG ($(du -h "$DMG" | cut -f1)) and $DIST/appcast.xml"

# A DMG that is not notarized is blocked by Gatekeeper on other Macs: never publish one by accident.
if [ "$DRY" = 0 ] && [ "$NOTARIZED" = 0 ] && [ "$ALLOW_UNNOTARIZED" = 0 ]; then
  cp "$DIST/Info.plist.bak" "$PLIST"
  echo "Not publishing: the DMG is not notarized (see the messages above). Fix that, or pass --allow-unnotarized to test."
  exit 1
fi

if [ "$DRY" = 1 ]; then
  cp "$DIST/Info.plist.bak" "$PLIST"
  echo "Dry run: version file restored, nothing committed or published."
  exit 0
fi

git add "$PLIST"
git commit -q -m "Version $VERSION"
git tag "$TAG"
git push -q origin main "$TAG"
gh release create "$TAG" "$DMG" "$DIST/appcast.xml" --title "Méliès $VERSION" --notes-file "$DIST/updates/Melies-$VERSION.md"

# Homebrew cask: rewritten from this template with the new version and checksum.
TAP="Benoitded/homebrew-melies"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
TAPDIR=$(mktemp -d)
if gh repo clone "$TAP" "$TAPDIR" -- -q 2>/dev/null; then
  mkdir -p "$TAPDIR/Casks"
  cat > "$TAPDIR/Casks/melies.rb" <<CASK
cask "melies" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/Benoitded/melies/releases/download/v#{version}/Melies-#{version}.dmg"
  name "Méliès"
  desc "Screen recorder and small video editor for the menu bar"
  homepage "https://github.com/Benoitded/melies"

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Melies.app"

  zap trash: [
    "~/Library/Preferences/dev.melies.app.plist",
    "~/Library/Caches/dev.melies.app",
  ]
end
CASK
  git -C "$TAPDIR" add -A
  git -C "$TAPDIR" commit -q -m "melies $VERSION"
  git -C "$TAPDIR" push -q && echo "==> Homebrew cask updated: brew install --cask $TAP/melies"
else
  echo "!! Homebrew tap $TAP not found: skipped (create it once, see docs/RELEASING.md)."
fi
echo "==> Published $TAG: installed apps will offer the update."
