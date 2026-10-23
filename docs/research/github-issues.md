# Competitors: what GitHub issues say (2026-10-22)

Report from a research subagent, reviewed and condensed. Data: all issues of the public repos
(`gh issue list`, PRs excluded), ranked by comments and reactions.

## Limits to keep in mind

- **Counts per theme are title matches only**, since April 2025 (Kap: since
  2021, because it only has 28 recent issues). They overlap, and some words are broad: they are
  orders of magnitude, not exact figures. About 35 issues read in detail out of about 3,000.
- Few reactions everywhere, except Kap (old issues with 40 to 80 thumbs up). Bug trackers
  over-represent breakages and under-represent silent satisfaction.
- Cap's tracker contains many bot-generated issues (security audits), which
  inflates the "cloud" theme.

## The repos

| Project | Stars | Activity | Issues | Note |
|---|---|---|---|---|
| Cap (Rust, Tauri) | 23.5k | daily | 806 (178 open) | open source recorder, Loom alternative |
| Kap (Electron) | 19.4k | last push 2024-11 | 840 (230 open) | no release since 2022 according to one issue, the community wonders whether it is abandoned |
| Recordly (Electron) | 34.8k | 2026-10-17 | 505 (268 open) | free copy of Screen Studio, all issues since March 2026 |
| OpenScreen | 39.9k | archived | 368 | continued in `getopenscreen/openscreen` (4.8k, active, 355) |
| Screenize (native Swift) | 0.6k | paused (May 2026) | 30 | small but very relevant |
| BetterCapture, better-shot, Azayaka (Swift) | 0.8 to 2.4k | varies | 34 to 105 | "native macOS app" signals |

## Recurring themes, in order of importance across repos

1. **Export reliability**: hangs, truncated or corrupted files, export differing from the preview,
   failures on large files. Largest bug category everywhere (hundreds of titles).
   E.g. Recordly: a one-minute video that comes out at 41 s, impossible to export more than 2 GB, hang at 99%.
   OpenScreen: "video decode ended early", corrupted MP4s. Cap: export frozen at 102% on 13 min.
   Screenize: the export does not match the preview.
2. **Audio**: missing or silent mic, system sound, echo, wrong device, offset,
   corruption on pause and resume, drift on long takes. Dominates Recordly (about 93
   titles) and remains Kap's oldest unresolved issue (system sound, open since 2017).
3. **Crashes at launch, start or stop, and recordings that produce nothing.**
4. **macOS permissions, signing and trust**: permission request loops, Gatekeeper "damaged" or
   "malware" warnings, unsigned apps. Screenize: the app automatically deleted by macOS after a
   signing key was revoked. Show up almost everywhere.
5. **Performance and memory**: memory that grows on long recordings (Cap: up to 15 GB),
   10-minute limit (OpenScreen: the whole recording fit in memory), CPU, slow export.
6. **Auto zoom, cursor smoothing, click effects**: the #1 wish ("why not like Screen Studio").
   Complaints are about bugs, not the idea: double cursor, smoothed cursor lagging
   behind clicks, offset in window capture, drift on long takes.
7. **Choice of capture target, multi-display**: 80 to 100 issues on Cap and Recordly.
8. **Editor basics**: undo, cut, split, shortcuts, merging clips, speed beyond
   2x.
9. **Annotations, blur, keyboard**: "blur is a basic feature" (OpenScreen), key display
   "essential for tutorials" (Cap).
10. **Output control**: recording folder, quality and bitrate, **estimated file size**,
    compression, GIF, Twitter format (Kap).
11. Webcam overlay, distribution (Homebrew requested in 4 repos), project health.

## What users like (little data)

Polished rendering and a "Screen Studio-like" result; free, no watermark or subscription; a maintainer
who answers quickly; for Kap, simplicity (menu bar, area, export).

## For Melies: what this implies

1. **Boring, infallible export**: exported duration equal to the source, preview identical to the export,
   progress with cancellation.
2. **Write to disk during capture** and be able to recover the last recording after a
   crash; never overwrite or move the source file (Screenize ate one).
3. **Audio as a first-class citizen**: separate tracks, right mic, device switching,
   no drift over 10 minutes and more, correct pause and resume. To be tested on long clips.
4. **Target-size export with an estimate before encoding**; bitrate chosen according to content (a bitrate
   that is too low makes text blurry: OpenScreen).
5. **Auto zoom from clicks and cursor, editable**. Avoid the traps: double cursor, smoothed
   cursor that lags, offset in window capture, drift. Record cursor telemetry at
   capture time (already done).
6. **Careful target selection**: area, window, display, remembering, display disconnection, black screen.
7. **macOS trust from the start**: developer signing and notarization, stable identifier, permission
   assistant, detection of "allowed but with no effect" with retry, automatic update, Homebrew.
8. **Editor basics before extras**; then annotations, blur, key display. If keys are
   captured, **never store the raw text** (Screenize: passwords were stored in plain text).
9. **Fast, light startup** (Kap: 3 to 10 s to show the selection, 45 to 61 reactions). A native
   app avoids Electron's class of bugs.
10. **Avoid**: cloud, accounts, transcription, marketplace; untested releases and
    regressions with every release; forgetting a macOS version (Sonoma, Sequoia, Tahoe, 27 beta).
