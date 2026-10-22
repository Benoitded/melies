# Méliès

Screen recorder and small video editor for the Mac menu bar, inspired by Shottr.
A global shortcut films a region of the screen, the editor opens straight on it, you trim and annotate, then
copy or drag a light MP4 (or GIF) into any app, for example Twitter / X.

Free, local (nothing leaves your Mac), Mac only. Named after Georges Méliès, the inventor of special effects
and editing on screen.

## Install

No version is published yet: the first release is waiting for Apple's notarization (see
[`docs/ROADMAP.md`](docs/ROADMAP.md)). Until then, [build it yourself](#build-it-yourself). Once a release exists:

### With Homebrew

```bash
brew install --cask Benoitded/melies/melies
```

(The cask lives in the `Benoitded/homebrew-melies` tap, which `Scripts/release.sh` updates after each release.)

### From the DMG

1. Download the latest `Melies-X.Y.Z.dmg` from [Releases](https://github.com/Benoitded/melies/releases).
2. Open the DMG and drag **Méliès** into **Applications**.

### First launch

1. Open Méliès: a film icon appears in the menu bar.
2. Allow **screen recording** when the app guides you (System Settings > Privacy & Security). The app restarts
   by itself once the switch is on.
   The **microphone** is only requested if you turn it on for a recording.

Requirements: **macOS 26 (Tahoe) or later**. Releases are built to be signed with a Developer ID and notarized by
Apple (`Scripts/release.sh` refuses to publish a DMG that is not notarized). Updates arrive through Sparkle
(menu bar menu > "Check for Updates...", or Settings > Advanced).

## Getting started

| Shortcut | Action |
|---|---|
| Cmd+Shift+6 | Draw the region and start recording; the same shortcut stops it (configurable) |
| Cmd+Shift+E | Reopen the editor on the latest recording (configurable) |
| Cmd+C / Cmd+S | In the editor: copy / save the optimized file (MP4, HEVC or GIF, as set in the export options) |

The full list is in [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md).

## What the editor does

- **Record** a region of the screen, with an optional **countdown** (3, 5 or 10 s, off by default; Settings > General).
- **Trim** the duration (I / O) and **crop** the frame (C).
- **Animated zooms** (Z) with adjustable speed and style, or **automatic zoom from the recorded clicks** (button
  in the zoom lane, three strengths: Subtle 1.5x, Normal 2x, Strong 2.6x; zooms that follow each other closely glide
  from one to the next instead of zooming out).
- **Annotations**: arrow, text, rectangle, spotlight, blur or pixelation. Blur, rectangle and spotlight have
  handles on the middle of each side as well as the corners.
- **Object tracking** for blur, spotlight, rectangle, text and arrow: the annotation follows the content (a blur
  follows scrolling text), forward and backward from the playhead. The path is drawn on the video, the editor says
  why tracking stopped, and a refresh button tracks again from the playhead.
- **Visible clicks**, **system sound** and **microphone**.
- **Combine two videos**: side by side, stacked, or picture in picture.
- **Export to a target size**: MP4 (H.264), the more compact HEVC (some apps reject it), or GIF; sizes from 1 to 100 MB
  or a custom value; 360p, 480p, 720p or 1080p. The panel shows a size estimate measured on a short test encode (a
  range when the content is simple). Esc cancels a running export.
- **Drag handle**: drag the result into a chat, an email or a browser. The editor steps aside while you drag, like Shottr.
- **Optional AI control**: a local MCP server (off by default) lets an AI app such as Claude Code edit the open
  video, see [`docs/AI.md`](docs/AI.md).
- Liquid Glass interface in **English, French, Italian and Spanish**.

## Troubleshooting

- *Recording does not start*: check System Settings > Privacy & Security > Screen & System Audio Recording,
  then relaunch the app.
- *No microphone sound*: turn the microphone on in the menu bar menu before recording, and accept the prompt.
- *The app is blocked when opening* ("Apple could not verify...", the case of a non-notarized copy, for example a
  pre-release or your own build): open System Settings > Privacy & Security, scroll down, and click **Open Anyway**
  next to Méliès. On macOS 15 and later, right-click > Open no longer bypasses the check.
- *The interface shows raw keys such as `mm.file`*: a language file is broken. Reinstall; when building yourself,
  `Scripts/build.sh` and `swift test` both check the language files.
- *"plugin for module 'SwiftUIMacros' not found" or "needs Xcode"*: the build needs the full Xcode, see below.
- *The AI app cannot connect*: Settings > Advanced shows the server status. A wrong key shows a red message, copy the
  command again (see [`docs/AI.md`](docs/AI.md)).

## Build it yourself

```bash
git clone https://github.com/Benoitded/melies && cd melies
Scripts/build.sh && open ~/Applications/Melies.app
```

This needs the full **Xcode 26 or later** (install it from the App Store; the Command Line Tools alone are not
enough and fail with "plugin for module 'SwiftUIMacros' not found"). If Xcode is installed but `xcode-select -p`
points to the Command Line Tools, the script uses the newest `/Applications/Xcode*.app` by itself, and prints how to
install Xcode when there is none. The script signs with your "Apple Development" certificate if you have one (ad hoc
otherwise), so macOS does not ask for permissions again after every build. It also checks every language file with
`plutil -lint` and installs the single copy in `~/Applications/Melies.app`.

Run the unit tests with `swift test` (auto zoom, language files, MCP export rules, request parsing). The `MELIES_*` test
hooks exist only in debug builds: a release build has none, unless you ask for them with `MELIES_HOOKS=1 Scripts/build.sh`.
To publish a version, see [`docs/RELEASING.md`](docs/RELEASING.md).

## Docs

- [`docs/DECISIONS.md`](docs/DECISIONS.md): why Swift, what was ruled out, how tracking, export and drag-and-drop work
- [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md): global and editor shortcuts
- [`docs/ROADMAP.md`](docs/ROADMAP.md): what is done and what is next
- [`docs/COMPETITORS.md`](docs/COMPETITORS.md): study of the other tools (details in `docs/research/`)
- [`docs/SHOTTR-REFERENCE.md`](docs/SHOTTR-REFERENCE.md): the Shottr conventions we follow
- [`docs/TWITTER-VIDEO.md`](docs/TWITTER-VIDEO.md): Twitter / X video constraints and what the export does
- [`docs/AI.md`](docs/AI.md): the optional AI layer (local MCP server)
- [`docs/RELEASING.md`](docs/RELEASING.md): publishing a version and updates

## License

To be chosen before the repository is advertised (see `docs/ROADMAP.md`).
