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
- [x] Object tracking: blur, spotlight, rectangle, text and arrow follow the content (scrolling, moving), forward and backward from the playhead, and stop when it disappears; the path is drawn on the video, the reason it stopped is shown, and a button tracks again
- [x] Edge handles in the middle of the sides of blur, rectangle and spotlight
- [ ] Priorities from the competitor study: see `docs/COMPETITORS.md`
- [x] Animated zooms: camera points (level, speed, style), automatic centering on the recorded cursor, identical preview and export
- [x] Motion blur during zoom and pan transitions (Off / Light / Strong, default Light), export only; the editor preview stays sharp
- [x] Cmd+Z / Cmd+Shift+Z (undo / redo: annotations, zooms, crop, trim)
- [x] Background, margins, rounded corners and shadow around the picture (gradient or solid presets), identical preview and export

## v3
- [x] Drag handle: the optimized MP4 can be dropped into any app
- [x] Two videos side by side, stacked, or picture in picture ("Combine" window, result reopened in the editor)
- [x] Audio: system sound and microphone while recording, sound kept or muted on export
- [x] Automatic zoom from recorded clicks (button in the zoom lane): clicks grouped by time and area, three strengths (Subtle, Normal, Strong), the camera glides between zooms that follow each other closely
- [x] Optional countdown before recording (3, 5 or 10 s, off by default)
- [x] Drag handle: the editor steps aside while the file is dragged (like Shottr)
- [x] Settings tabs aligned at the top, window follows the size of the content
- [x] Cancellable export with progress (Esc)

## AI (see `docs/AI.md`)
- [x] Editing tool layer (JSON facade over `EditorModel`)
- [x] Local MCP server (optional, off by default)
- [x] MCP feedback: status line and checklist in Settings, badge in the editor
- [x] MCP hardening: key in the Keychain, export limited to safe folders and never overwriting, bounded requests
- [ ] Screen recording tools
- [ ] Chat panel with an API key

## Distribution
- [x] Automatic updates (Sparkle, signed feed on GitHub Releases)
- [x] One-command release script (`Scripts/release.sh`, see `docs/RELEASING.md`)
- [x] README with install instructions
- [x] Unit tests (`swift test`): auto zoom, language files, MCP export rules and request parsing
- [x] Release script checks: notarization validated, draft-then-publish order, strict version
- [x] Test hooks compiled out of release builds
- [ ] First notarized release (Developer ID signing works, waiting for Apple to accept the first notarization; no GitHub release exists yet)
- [ ] Homebrew tap (`brew install --cask Benoitded/melies/melies`): the release script writes the cask, but the `Benoitded/homebrew-melies` repository still has to be created
- [ ] GitHub Actions CI (build + tests): there is no workflow yet, tests are run by hand with `swift test`

## Later
- [ ] Open source: choose a license, README with a demo GIF
