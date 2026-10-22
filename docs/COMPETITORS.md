# Competitors: summary and roadmap (2026-10-22)

Three studies, summarized here, with details in `docs/research/`:
- `blogs-and-reviews.md`: vendor pages, comparisons, feature and price matrix;
- `forums.md`: user reviews (Hacker News, Product Hunt, Setapp, Screen Studio feedback forum);
- `github-issues.md`: issues from public repos (Cap, Kap, Recordly, OpenScreen, Screenize, three Swift apps).

**Shared limits:** Reddit could not be read (tools refused); neither could X and Bluesky; many
sources are competitor pages; issue counts come from titles only. The conclusions are strong
hints, not statistics.

## What the three studies say together

| Finding | Forums | GitHub issues | Blogs and prices |
|---|---|---|---|
| **Reliability matters more than the number of features** | #2 among qualities cited | crashes, broken exports, regressions with every release | CleanShot X 5.0 breaks after an update (Setapp review) |
| **Export must be reliable and identical to the preview** | heavy or unreadable exports | top bug category in every repo | n/a |
| **Audio is the top source of bugs** | requested everywhere | missing mic, drift, pause that corrupts | present in almost all |
| **Target-size export** | requested from Screen Studio, **refused** | requested on Kap, OpenScreen, Cap | only generic presets |
| **Honest price, no subscription** | #1 among qualities cited | n/a | Screen Studio removed the one-time purchase |
| **macOS trust (signing, permissions)** | n/a | "malware", app deleted, permission loops | n/a |
| **Auto zoom, cursor, clicks** | wanted, with zoom that can be turned off | the bugs, not the idea (double cursor, lag) | CleanShot X 5.0 just added it |
| **Local first, no account** | requested | Cap's cloud = 130 issues, mostly noise | differentiator for Shottr, Xnapper, Recordly |
| **Annotations with a duration in the video** | requested (CleanShot) | blur "basic feature" | few competitors do it well |

**Main threat:** CleanShot X 5.0 (September 2026) moves into Méliès's space (Studio mode,
smart zooms, cursor smoothing, backgrounds). Try it for real before deciding.

## Where Méliès stands

| Expected feature | Status |
|---|---|
| Area, trim, crop, undo | done |
| Animated zoom (points, speed, styles), centering on the cursor | done |
| Annotations with a duration: arrow, text, rectangle, spotlight, blur | done |
| Visible clicks | done |
| Mic and system sound, sound muted or kept on export | done (mic to be tested) |
| Combine two videos | done (rare among the competitors read, not specifically searched) |
| File drag-and-drop handle | done (the drop still needs trying) |
| Target-size export, GIF | **done** (options panel: MP4 or GIF, maximum size, resolution) |
| Export identical to preview | by construction (same drawing), to be tested on real cases |
| Cursor smoothing | camera follow only (Off / Light / Smooth); the baked-in real cursor is not redrawn, so not on par yet |
| Auto zoom from clicks | done (three strengths, glides between close zooms); quality against CleanShot X 5.0 not compared yet |
| Background, margins, rounded corners, shadow | done (gradient or solid presets, identical preview and export) |
| Webcam overlay | to do |
| Countdown | done (3, 5 or 10 s, optional) |
| Pause, window or full-screen target | to do |
| Object tracking for blur, spotlight, rectangle, text and arrows | done (pixel matching, both directions from the playhead; Vision was tried first and dropped) |
| Key display | to do, never storing the typed text |
| Developer signing and notarization | signing works, first notarization pending |
| Still screenshots (scrolling, OCR) | out of scope for now |

## Proposed roadmap

1. ~~Target-size export and GIF~~: done. Still to decide: a one-click "Twitter / X" preset.
2. **Recording and export reliability**: recovery of the last recording after a
   crash, testing of long recordings (10 min and more) with audio, testing with each macOS release.
   Export progress and cancellation (Esc) are done, and the first unit tests exist (`swift test`).
3. ~~Auto zoom from clicks~~: done, editable like the other zoom points.
4. **Background, margins, rounded corners, shadow**, with presets.
5. ~~Object tracking~~ for blur, spotlight, rectangle, text and arrows: done.
6. **Choice of target**: window, full screen, remembered area; pause (the countdown is done).
7. **macOS trust**: signing and automatic update (Sparkle) are in place; notarization and Homebrew are waiting for the first release.
8. Webcam overlay; key display.

## What not to do

Cloud, accounts, share links, view analytics, AI transcription, plugin marketplace, subscription
only, features that disappear for buyers, Electron.

## Pricing (to be decided later)

The three studies converge: one-time purchase with one year of updates and optional renewal,
never a subscription alone. Benchmarks: Shottr about $12, ScreenFloat $18, CleanShot X $35, Cap $58,
Screen Studio $108 per year.
