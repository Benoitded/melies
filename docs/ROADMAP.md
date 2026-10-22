# Roadmap

## v1 (done)
- [x] Native screen recording (ScreenCaptureKit, region of your choice) with Cmd+Shift+6
- [x] Red stop button in the menu bar, editor opens automatically
- [x] Menu bar app with icon, menu, Settings and shortcut list
- [x] Global shortcut that opens the editor on the latest video from the Desktop
- [x] Trim (I / O) with looped playback
- [x] Twitter export: Cmd+C (copy the file), Cmd+S (save)
- [x] Drag and drop, Cmd+Shift+O, Cmd+Shift+V

## v2
- [x] Frame crop (handles, applied on export)
- [x] Frame previews on the timeline, checkerboard behind the video
- [x] Tabbed Settings (General, Hotkeys, Advanced), light / dark / system theme
- [x] Arrows, text, rectangle (settings panel, duration on the timeline)
- [x] Spotlight (lit area), blur and pixelation
- [x] Visible clicks: a ring expands at every recorded click (color and size adjustable)
- [x] Export to a target size (MP4, GIF), resolution, size estimate; copy, save, share and drag all follow these settings
- [x] More compact export: sizes from 1 to 100 MB (or custom), 360p to 1080p, HEVC
- [x] Object tracking: blur, spotlight, rectangle, text and arrow follow the content (scrolling, moving) and stop when it disappears
- [ ] Priorities from the competitor study: see `docs/COMPETITORS.md`
- [x] Animated zooms: camera points (level, speed, style), automatic centering on the recorded cursor, identical preview and export
- [x] Cmd+Z / Cmd+Shift+Z (undo / redo: annotations, zooms, crop, trim)

## v3
- [x] Drag handle: the optimized MP4 can be dropped into any app
- [x] Two videos side by side, stacked, or picture in picture ("Combine" window, result reopened in the editor)
- [x] Audio: system sound and microphone while recording, sound kept or muted on export
- [x] Automatic zoom from recorded clicks (button in the zoom lane)
- [x] Cancellable export with progress (Esc)

## AI (see `docs/AI.md`)
- [x] Editing tool layer (JSON facade over `EditorModel`)
- [x] Local MCP server (optional, off by default)
- [ ] Screen recording tools
- [ ] Chat panel with an API key

## Distribution
- [x] Automatic updates (Sparkle, signed feed on GitHub Releases)
- [x] One-command release script (`Scripts/release.sh`, see `docs/RELEASING.md`)
- [x] README with install instructions
- [ ] First notarized release (Developer ID signing works, waiting for Apple to accept the first notarization)
- [ ] Homebrew tap (`brew install --cask Benoitded/melies/melies`)
- [ ] GitHub Actions CI (build + tests)

## Later
- [ ] Open source: choose a license, README with a demo GIF
