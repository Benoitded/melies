# Publishing a version

One command, from a clean `main`:

```bash
Scripts/release.sh            # 0.1.0 -> 0.1.1
Scripts/release.sh minor      # 0.1.1 -> 0.2.0
Scripts/release.sh 1.0.0      # an exact version
Scripts/release.sh --dry-run  # builds everything in dist/, publishes nothing
Scripts/release.sh 0.1.1 --dry-run --skip-notarization  # fast DMG while Apple has not answered (Gatekeeper will warn)
Scripts/release.sh --allow-unnotarized                   # publish even without notarization (tests only)
```

Options:

| Option | Effect |
|---|---|
| `--dry-run` | Builds the app, DMG and `appcast.xml` in `dist/`; does not touch the repository or GitHub; restores the version file |
| `--skip-notarization` | Does not submit to Apple (fast pre-release builds, Gatekeeper will warn) |
| `--allow-unnotarized` | Lets a real publish go through with a DMG that is not notarized. Without it, the script refuses to publish one |

The version argument is `patch` (default), `minor`, `major` or an exact `X.Y.Z`. Anything else is refused: the version
must be three dot-separated numbers.

What the script does, in order:

1. Checks (real run only): clean working tree, branch `main`, `gh` logged in, tag not already used.
2. Bumps `CFBundleShortVersionString` and `CFBundleVersion` in `Scripts/Info.plist` (restored if a step fails before the commit).
3. Builds and signs the app with `Scripts/build.sh` (Developer ID and hardened runtime when the certificate exists,
   found by its SHA-1 hash), then makes the DMG and signs it.
4. Notarizes and staples the DMG when the `melies-notary` profile exists, then checks it: `stapler validate` and
   `spctl -a -t open` must both pass, otherwise the script stops.
5. Signs the update for Sparkle and writes `appcast.xml`. Release notes are the commit subjects since the previous
   tag: one clear commit per task is enough.
6. Publishes in an order that never leaves half a release: commit locally, create the GitHub release as a **draft**,
   push the commit and the tag, then publish the draft. If creating the draft fails, the local commit is undone; if the
   push fails, the draft and the tag are removed.
7. Rewrites the Homebrew cask (version and sha256) in the tap and pushes it. A tap that is missing or cannot be
   pushed only prints a warning; the release itself stays published.

```mermaid
flowchart LR
  R[release.sh] --> V[Version +1] --> B[Build + signing]
  B --> D[DMG] --> N[Notarization + stapling]
  N --> S[Sparkle signature + appcast.xml]
  S --> G[Tag + GitHub release]
  G --> H[Homebrew cask updated]
  G --> U[Installed apps offer the update]
```

## Pre-release while Apple is slow

Notarization can take hours the first time. To share a build before it is accepted, build a DMG without notarization
(`--dry-run --skip-notarization` writes it to `dist/updates/`) and publish it by hand as a GitHub **pre-release**. A pre-release is never "latest": automatic
updates and Homebrew ignore it. People open it once with System Settings > Privacy & Security > "Open Anyway". The
real release (notarized) replaces it later.

## One-time setup

1. **Certificate**: Xcode > Settings > Accounts > Manage Certificates > "+" > *Developer ID Application*.
   Without it the script still builds (signed for development) but the app will not open without a warning on
   another Mac. The script finds the certificate by its SHA-1 hash, not its name: names with accents get mangled
   when passed through the shell.
2. **Notarization**: create an app-specific password at account.apple.com, then, in your own Terminal:
   ```bash
   xcrun notarytool store-credentials melies-notary --apple-id YOUR_APPLE_ID_EMAIL --team-id YOUR_TEAM_ID
   ```
   (the password is prompted for and stays in the keychain; never paste it anywhere else).
3. **Sparkle key**: generated once in the keychain ("Private key for signing Sparkle updates"). **Back it up**:
   without it no update can be signed for already installed apps. Export it to a file, open the file in a text
   editor (never print it in a shared terminal or chat), copy it into a password manager, then delete the file:
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Documents/melies-sparkle-key.backup
   ```
   If the private key ever leaks, replace it before publishing: delete the keychain item
   (`security delete-generic-password -s "https://sparkle-project.org" -a ed25519`), run `generate_keys` again, and
   put the new public key in `Scripts/Info.plist` (`SUPublicEDKey`). Apps already released with the old key could
   not be updated any more, so do this before the first release if you can.
4. **Public repository**: the app reads `appcast.xml` and downloads the DMG from GitHub without credentials.
   While the repository is private nobody but you can receive updates.
5. **Homebrew tap**: the repository `Benoitded/homebrew-melies` holds `Casks/melies.rb`. The release script
   rewrites it (version and sha256) after each release. Users install with
   `brew install --cask Benoitded/melies/melies`. If the tap is missing the script only prints a warning
   (at the time of writing that repository could not be found: create it once before the first release).

## Where things are set

| What | Where |
|---|---|
| Feed URL, public key, check frequency | `Scripts/Info.plist` (`SUFeedURL`, `SUPublicEDKey`, `SUScheduledCheckInterval`) |
| Menu item, automatic setting | `Sources/Melies/Updater.swift`, Advanced tab |
| Signing (hardened runtime, Sparkle inside out), microphone entitlement | `Scripts/build.sh`, `Scripts/Melies.entitlements` |
| Language file syntax check (`plutil -lint`), Xcode detection | `Scripts/build.sh` |
| Test hooks in a build (never for a real release) | `MELIES_HOOKS=1 Scripts/build.sh` |
| Cask template | `Scripts/release.sh` (last step) |
