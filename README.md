# Méliès

Screen recorder and small video editor for the Mac menu bar, inspired by Shottr.
A global shortcut films a region of the screen, the editor opens straight on it, you trim and annotate, then
copy or drag a light MP4 (or GIF) into any app, for example Twitter / X.

Free, local (nothing leaves your Mac), Mac only. Named after Georges Méliès, the inventor of special effects
and editing on screen.

## Install

### With Homebrew

```bash
brew install --cask Benoitded/melies/melies
```

### From the DMG

1. Download the latest `Melies-X.Y.Z.dmg` from [Releases](https://github.com/Benoitded/melies/releases).
2. Open the DMG and drag **Méliès** into **Applications**.

### First launch

1. Open Méliès: a film icon appears in the menu bar.
2. Allow **screen recording** when the app guides you (System Settings > Privacy & Security). The app restarts
   by itself once the switch is on.
   The **microphone** is only requested if you turn it on for a recording.

Requirements: **macOS 26 (Tahoe) or later**. The app is signed and notarized by Apple. Updates arrive by
themselves (menu bar menu > "Check for Updates...", or Settings > Advanced).

## Getting started

| Shortcut | Action |
|---|---|
| Cmd+Shift+6 | Draw the region and start recording; the same shortcut stops it (configurable) |
| Cmd+Shift+E | Reopen the editor on the latest recording (configurable) |
| Cmd+C / Cmd+S | Copy / save the optimized MP4 |

The full list is in [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md).

## What the editor does

- **Trim** the duration (I / O) and **crop** the frame (C).
- **Animated zooms** (Z), placed automatically on recorded clicks if you want, with adjustable speed and style.
- **Annotations**: arrow, text, rectangle, spotlight, blur or pixelation, with **object tracking** (a blur
  follows scrolling text).
- **Visible clicks**, **system sound** and **microphone**.
- **Combine two videos**: side by side, stacked, or picture in picture.
- **Export to a target size**: MP4 (H.264), the more compact HEVC, or GIF; from 360p to 1080p; any size limit
  (1 MB and up) to fit Twitter / X, Slack and similar limits.
- **Drag handle**: drag the result into a chat, an email or a browser.
- Liquid Glass interface in **English, French, Italian and Spanish**.

## Troubleshooting

- *Recording does not start*: check System Settings > Privacy & Security > Screen & System Audio Recording,
  then relaunch the app.
- *No microphone sound*: turn the microphone on in the menu bar menu before recording, and accept the prompt.
- *The app is blocked when opening*: right-click Méliès > Open (case of a non-notarized copy).

## Build it yourself

```bash
git clone https://github.com/Benoitded/melies && cd melies
Scripts/build.sh && open ~/Applications/Melies.app
```

This needs the full **Xcode 26 or later** (install it from the App Store; the Command Line Tools alone are not enough and fail with "plugin for module 'SwiftUIMacros' not found"). If Xcode is installed but `xcode-select -p` points elsewhere, the script finds it by itself. The script signs with your "Apple Development" certificate if you have one, so
macOS does not ask for permissions again after every build. To publish a version, see
[`docs/RELEASING.md`](docs/RELEASING.md).

## Docs

- [`docs/DECISIONS.md`](docs/DECISIONS.md): why Swift, what was ruled out, how tracking and export work
- [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md): global and editor shortcuts
- [`docs/ROADMAP.md`](docs/ROADMAP.md): what is done and what is next
- [`docs/COMPETITORS.md`](docs/COMPETITORS.md): study of the other tools
- [`docs/TWITTER-VIDEO.md`](docs/TWITTER-VIDEO.md): Twitter / X video constraints and what the export does
- [`docs/AI.md`](docs/AI.md): the optional AI layer (local MCP server)
- [`docs/RELEASING.md`](docs/RELEASING.md): publishing a version and updates

## License

To be chosen before the repository is advertised (see `docs/ROADMAP.md`).
