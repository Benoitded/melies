# Decisions

## Mac only, Swift / SwiftUI (2026-10-20)

Choice: native Swift + SwiftUI + AVFoundation app, in the menu bar.

Why:
- Personal Mac tool, no need for cross-platform or a web version.
- Menu bar, global shortcut, clipboard (copying a video file), hardware H.264
  encoding and the system design (Liquid Glass) are all native.
- Later, ScreenCaptureKit will allow recording the screen natively.

Rejected: Tauri + WebCodecs. Tried as a spike: the Vite server crashed under
Node 20.17 (Vite 8 requires Node 20.19+ or 22+), and encoding inside a webview
was still unproven. All the Tauri code was deleted, nothing of it is kept.

Rejected: local web page with ffmpeg. Cannot have a global shortcut.

## Name: Méliès (2026-10-20)

Georges Méliès invented the jump cut, the superimposition and the on-screen
special effect: exactly what the tool does (cut, overlay, zoom).
Command and folder name: `melies`, without the accent.

Rejected: `clipr` (too many homonymous products: Twitch downloader, UGC platform,
clipboard manager), `motionr` (available but soulless).
Checked on npm, Homebrew, GitHub only. Trademarks and App Store not checked.

## Global shortcuts: KeyboardShortcuts library

Shottr itself uses `sindresorhus/KeyboardShortcuts` (visible in its
bundle). We do the same: configurable shortcut in Settings.

## Signing

Apple Developer account available. Daily builds (`Scripts/build.sh`) are signed with the Mac's "Apple Development"
identity if present, otherwise ad hoc, so macOS keeps the permissions between builds. Releases
(`Scripts/release.sh`) are signed with a Developer ID and the hardened runtime, notarized, and refuse to publish a DMG
that is not notarized (see `docs/RELEASING.md`). Update (2026-10-22): the first notarization is still pending.

## Open source

Planned for later, under the team's GitHub. Mac only (like Shottr).
Before publishing: check the name (trademarks, App Store), add a license,
put nothing specific to Byzantine in the code.

## Built-in screen recording (2026-10-20)

Requested from v1: Cmd+Shift+6 starts and stops. Implemented with
ScreenCaptureKit (`SCRecordingOutput`; the app as a whole now requires macOS 26), area drawn on a
full-screen overlay, H.264 60 fps .mov file in the watched folder, then
the editor opens on it. Stopping is done with the same shortcut or the red
button in the menu bar. Asks for the "Screen Recording" permission
on first launch.

## Animated zooms and a custom video compositor (2026-10-20)

Zooms are camera points (time, level, center, travel duration, style)
laid out on a track under the timeline. Z creates a zoom with a start and an end, then
adds intermediate points that pick up the camera's current state. The
level is interpolated on a logarithmic scale, the center linearly, with a
choice of style (smooth, snappy, linear, spring).

Export no longer uses constant-transform AVFoundation instructions: a custom
`AVVideoCompositing` (Core Image) computes each frame: rotation, crop,
camera, scaling and black bars. Arrows, text and rectangles will be
drawn in the same place, so the preview and the export match. Verified with a
fixed test pattern: identical full frame (49 dB), x2 zoom on the right region.

During recording, the cursor position is sampled at 30 Hz and written to
`<name>.cursor.json` next to the video. A new zoom is centered on the mouse at that instant.

## Tool settings: floating panel (2026-10-20)

Inspired by Shottr, observed directly in the app: when an object is selected, a small floating
panel appears at the top right of the image (chevron to collapse it, color,
thickness as a wedge-shaped slider, styles as icon buttons). Same components
(`ToolPanel`, `IconSegments`, `WedgeSlider`) for zoom points now, and for
arrows, text and rectangles afterwards. The zoom track draws the zoom level
curve so you can see the dynamics at a glance.

## Liquid Glass wherever something floats (2026-10-22)

Minimum macOS 26, no fallback code: personal tool on a Mac running macOS 27. Glass is used for
surfaces that float above the content, never for the content itself: the three capsules of the
toolbar (`GlassEffectContainer`), the tool settings panel, the tooltips, the
"Copied" bubble, the play button and the empty-screen buttons (`.buttonStyle(.glass)`), the
main button of the welcome screen (`.glassProminent`). The timeline, the zoom track and the video
remain content. Settings use AppKit's native toolbar style.

Pitfall: off-screen rendering (`cacheDisplay`) does not draw the glass. To judge the appearance, you
have to capture the real window (the app must be launched with its window open to be
targetable by the capture tool).

## Annotations: a single drawing for preview and export (2026-10-22)

Arrow, text and rectangle are objects with a duration (start, end) and a geometry normalized
in the source image: they therefore follow the crop and the animated zooms. `AnnotationRenderer` draws
them in Core Graphics in source pixel space; the preview (SwiftUI Canvas) and the export
(Core Image compositor) only apply a different transform. Settings (color,
thickness or size, style, font) are remembered per object type.

Pitfall: single-key shortcuts (A, T, R...) are hidden buttons; they are disabled
while typing text (`isEditingText`), otherwise typing "a" would launch the arrow tool.

## Welcome screen in real Liquid Glass, layered icon (2026-10-22)

The welcome screen is an `NSGlassEffectView` window: the content stays flat on top (no glass on
glass). The icon is an Icon Composer file `Resources/Melies.icon` (gradient background, film strip,
glass play button) compiled by `actool` into `Assets.car` plus a fallback `.icns`.

## Undo / redo by sequences (2026-10-22)

A snapshot of the editable state (annotations, zoom points, crop, trim start and end) is
pushed on the first change of a sequence. Changes less than 0.6 s apart form
a single sequence, so one drag, one slider or one keystroke = a single step. No per-gesture
recording in the code: a `didSet` on these five properties is enough. Navigation (playhead,
selection, canvas zoom) is not in the history. While typing text,
Cmd+Z belongs to the text field.

## Lessons from mouse testing (2026-10-22)

- An annotation created under the playhead at its very start was invisible (fade-in at
  0). The editor now shows objects fully when playback is paused.
- The text field was not active right after a text was created: typed letters
  triggered shortcuts (I, O, A, V...). Focus is now taken when the panel appears.

## Combining two videos: one file, then the editor (2026-10-22)

Choice: "Combine" produces a new MP4 (side by side, stacked or picture-in-picture) which
then opens in the editor, rather than making the whole editor multi-track. Reason: crop,
zooms, annotations and trim remain written for a single video; combining
is an upstream step, simple to understand. Trade-off: one more encode (maximum
quality to limit the loss).

The compositor (`ComposeCompositor`) draws the two videos with the same geometry as the window
preview (`ComposeGeometry`). When one video ends before the other, its last frame stays
displayed. The picture-in-picture has rounded corners, a hairline border and a shadow. The sound of both videos is
kept if present.

## Spotlight and blur (2026-10-22)

The spotlight darkens everything except one area (drawn like the other annotations). Blur and
pixelation change the video's pixels: they are applied on the source image before
the crop and the camera, so the pattern follows the zoom. The preview reads the last decoded frame of the player
(`AVPlayerItemVideoOutput`) and uses the same filter as the export. Pixelation by default: a light
blur can sometimes be undone, large blocks cannot.

## Drag-and-drop handle (2026-10-22)

The toolbar handle (empty area between two groups of dots, like Shottr) provides the optimized
MP4 when the destination app asks for it: `NSItemProvider` with a lazy file representation
(like a file promise). The export therefore only happens at drop time, not at every
change. Dragging neither saves nor closes anything: it is a sharing gesture, not an exit.
## Audio (2026-10-22)

System sound (`capturesAudio`) and the microphone (`captureMicrophone`, macOS 15) go through
ScreenCaptureKit and are written to the same file by `SCRecordingOutput`. Both options are
off by default (privacy), adjustable in Settings and in the menu bar
menu. The microphone asks for permission the first time; if denied, recording continues
without the voice and a bubble says so.

A recording can have several audio tracks: the export mixes them into a single track
(`AVMutableAudioMix`), or sets them to zero if the editor's sound button is muted. Test pitfall:
launched directly from a terminal, the app does not inherit the screen recording permission
(macOS grants it to the parent program); it must be started with `open -a` to test capture.

## Visible clicks (2026-10-22)

Clicks are recorded alongside the cursor position (`<name>.cursor.json` becomes an object
`{cursor, clicks}`; the old plain array can still be read). Nothing is drawn into the
original video: the ring is computed at render time, so it can be turned on, off, and its color and
size changed afterwards, and it follows the crop and the zooms. Only clicks inside the recorded area
count. The smoothed cursor is not done: it would require recording without the real cursor and
redrawing it, which loses the shapes (arrow, text bar, hand).

## Keyboard shortcuts: direct key listening (2026-10-22)

Single-key shortcuts (V A T R S B C Z I O, Space, arrows, Delete, Return, Escape) used to be
carried by invisible SwiftUI buttons (opacity 0, size 0): they received no keys.
They are now read from the keyboard events of the editor window
(`NSEvent.addLocalMonitorForEvents`), only when it is the active window, not while typing
text (the first responder is a text editor) and not with Cmd, Option or Control (those are
menu items). Letters are read with `charactersIgnoringModifiers`, so they are keyboard-independent
(AZERTY included). Delete = Backspace (51) and Forward Delete (117).
Test pitfall: the automation tool sends keys to a background window, which is not
"active"; to test, the app must be activated first.

## Blur when paused (2026-10-22)

The player no longer delivers frames when paused, and the time observer only runs
during playback. The blur preview therefore requests the exact frame under the playhead itself
(`AVAssetImageGenerator`) when an annotation is added, at each move and when pausing.

## Stable timeline bars and a handle that does not move the window (2026-10-22)

- Annotation bars were ordered by start time: delaying the start of the top bar
  made it go below the other, and the drag in progress landed on the wrong bar. Rows now follow
  creation order, and are frozen during a drag.
- The drag-and-drop handle is in the title bar area, where pressing the mouse moves the
  window. It is now an AppKit view (`mouseDownCanMoveWindow = false`) that starts a real "promised"
  file drag (`NSFilePromiseProvider`): the MP4 is only exported at drop time.

## Target-size export and GIF (2026-10-22)

Export no longer uses the `AVAssetExportSession` preset (bitrate not adjustable): `AVAssetReader`
reads the composed frames (the same compositor as the preview), `AVAssetWriter` encodes H.264 at a
**computed bitrate** aiming at the chosen size (93% of the target, minus audio at 128 kb/s). If the file
still exceeds it, it encodes again with a corrected bitrate (three attempts at most). With no limit, the bitrate follows the number of
pixels. The GIF is written with ImageIO; with a maximum size, it tries decreasing widths and frame rates
(720 px at 15 fps down to 128 px at 3 fps) until the file fits. If nothing fits,
the actual size is shown.

Pitfall: `URL.resourceValues(forKeys: [.fileSizeKey])` caches the value on the URL object; re-read after
each attempt, it returned the size of the first one. The size is now read with
`FileManager.attributesOfItem`.

The audio is a single AAC stream (system and microphone tracks are mixed); without audio, the file has no
audio track at all.

## Object tracking (2026-10-22)

First attempt with `VNTrackObjectRequest` (Vision): fine for a moving object, but it gets lost on
scrolling text (low-texture area, repeated patterns) and does not say when the object disappears. Replaced by a
pixel comparison: the starting area (grayscale, image downscaled to ~640 px) is searched on each
frame around its last position, first coarsely then finely; the model adapts slowly to
appearance changes. If the mean difference exceeds 10% for more than 0.12 s (scrolled out of frame, window
passed in front), tracking stops and the annotation ends at that instant. The offsets are stored per
annotation (`Annotation.track`) and applied at render, at selection and at export.

Update (2026-10-22): tracking now runs in both directions from the playhead (a forward pass, then a backward pass on
the frames before it), so it can be started in the middle of an annotation; where the object was not yet visible, the
annotation starts there. The editor draws the path found so far on the video, says why tracking stopped (left the
frame, or covered or changed), and offers a button to track again from the playhead. The loss threshold is now
relative to the contrast of the area (mean luma difference above 0.5) instead of a fixed 10%, still with the 0.12 s
tolerance. It works for blur, spotlight, rectangle, text and arrow.

Tuning: the difference is judged against the area's contrast (a flat area does not "stick" by chance), and an
area that touches a frame edge it did not touch at the start is considered to be leaving. Measured on generated
videos: scrolling at 100 px/s, area lost at 2.5 s (expected 2.5 s); area masked at 1.5 s, lost at 1.5 s.

## Drag-and-drop: a real file (2026-10-22)

"File promises" (`NSFilePromiseProvider`) are not accepted by Chrome nor by many chat apps or
upload pages. When the pointer arrives on the handle, the result is now exported in advance
to a temporary file (invalidated on every edit or export setting change) and the drag
carries that file. The promise remains the fallback if the export is not ready yet.
Update (2026-10-22): the editor now steps aside during the drag, see the drag source entry at the end.

## Export options: smaller, more compact (2026-10-22)

Sizes 1, 2, 3, 5 MB in addition to the previous ones, free entry via "Other...", 360p and 480p resolutions, and an
HEVC (H.265) format: about 40% smaller at equal quality (3.4 MB in H.264 versus 2.1 MB on a 10 s test),
but Twitter/X and some apps may reject it, hence the note in the panel.

## Tracking on scrolling text (2026-10-22)

First attempt on a real recording (scrolling chat, up to ~130 px per frame): area lost at the first
jump. Three causes: the downscale took one pixel out of three (fine text distorted as soon as it
moved by a fraction of a pixel), the best alignment on text is a one-pixel trough that the
coarse search (3 px step) stepped over, and the search window was too narrow for fast scrolling.
Now: downscale by block averaging, coarse search on a blurred copy then refinement on the
sharp image, search centered on the predicted position (last displacement) with a window of one third of the height.
Test pitfall: the noise image generated by `geq` was periodic (120 px), so the tracking found real
duplicates; ffmpeg's `noise` filter gives non-periodic noise.

## Drag source: our own tracking loop (2026-10-22)

Problem: the drag handle sits in the title bar area, and macOS treats a mouse press there as the start of a window drag.
Handled the usual way (`mouseDown`, then `mouseDragged`), the system took over after a couple of moves: the window
followed the pointer and the file drag never ended properly (session stuck).

Fix (`DragSourceNSView` in `TopBar.swift`):
- `mouseDownCanMoveWindow` is false, and `mouseDown` runs its own event loop (`nextEvent`) from the press to the release.
  A release without movement is a plain click; a movement of more than 3 points starts the file drag.
- Like Shottr, the editor steps aside during the drag: it fades out and ignores the mouse, so it never covers the
  destination (the app behind, a chat window). It comes back when the drag ends, wherever it ends.
- If macOS moved the window anyway, its frame is restored (it is invisible meanwhile) before it is shown again.
- Safety net: if the drag never reports its end, the editor comes back once the mouse button has been up for 1.5 s.

## Broken English strings file (2026-10-22)

Incident: a string in `Localization/en.lproj/Localizable.strings` contained straight double quotes inside its value
(`"%@"` around a file name). One bad line makes macOS ignore the whole file, so the app showed raw keys everywhere
(`mm.file`, `exp.nolimit`, ...), not only the faulty message.

Fix and guards:
- The line now uses typographic quotes.
- `Tests/MeliesTests/LocalizationTests.swift` checks that each of the four language files (en, fr, it, es) parses, that
  all have the same keys as English, and that format placeholders (`%@`, `%d`, ...) match.
- `Scripts/build.sh` runs `plutil -lint` on every `.strings` file and stops the build on an invalid one.
- Rule: a quote inside a localized value is either escaped (`\"`) or typographic.

## Security review outcome (2026-10-22)

The local MCP server lets an AI app drive the editor, so its inputs are treated as untrusted. Changes:
- Export through MCP (`export` tool): the path must be inside Movies, Desktop, Documents, Downloads, Pictures, the watched
  folder, the folder of the open video or the temporary folder (symbolic links resolved; hidden folders and `.app`
  bundles refused). The extension is forced by the app, and an existing file is never overwritten (`-2`, `-3`...).
  Covered by unit tests.
- The MCP key is stored in the Keychain (this device only, while unlocked), no longer in the preferences file; an old
  key found there is moved. "New key" replaces it.
- Server limits: exact `Host` and `Origin` host check, request body at most 1 MB, at most 8 connections, 30 s to send
  a request, ambiguous requests (two `Content-Length`, chunked body) refused, 120 s deadline per tool call.
- Test hooks (`MELIES_*` environment variables) are compiled only into debug builds, or with `MELIES_HOOKS=1
  Scripts/build.sh`. A release build has none, so no environment variable can change what the published app does.
- Also changed in the same pass: the microphone entitlement is declared (needed once the hardened runtime is on),
  temporary files are cleaned up, and the release script checks notarization and publishes as a draft first.
