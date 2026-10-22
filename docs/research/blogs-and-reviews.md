# Competitors: blogs, vendor pages, comparisons (2026-10-22)

Report from a research subagent, reviewed and condensed. Sources: official pages (features, prices,
changelogs), comparisons (The Sweet Bits, Setapp), GitHub pages. Stated limits: no usable
MacStories, 9to5Mac, Zapier or TechRadar article; no Product Hunt or Hacker News threads
(except the Cap reviews); Screen Studio's changelog was empty; several GitHub pages without release
dates. A "?" cell means not verified, not "no".

## The key fact

**CleanShot X 5.0 (September 1, 2026)** adds a Studio mode and a video editor: smart zooms,
cursor smoothing, motion blur, custom backgrounds, cursor size after the fact, keys and camera,
hardware-encoded export. The reference capture tool is therefore moving into Méliès's space.
Price: $35 once (one year of updates). To be tested for real: the quality of its smart zooms is
unknown.

## Matrix (excerpt, products close to Méliès)

| Feature | CleanShot X | Screen Studio | Cap | Recordly | OpenScreen | Screenize |
|---|---|---|---|---|---|---|
| Mic | yes | yes | yes | yes | yes | yes |
| System sound | yes | yes | ? | yes | yes | yes |
| Webcam | yes | yes | yes | yes | yes | ? |
| Cursor (click, smoothing, size) | yes | the most complete | ? | yes | yes | yes (ripple) |
| Auto zoom | yes (Smart Zooms) | yes | ? | yes (suggestions) | yes | yes (2 modes) |
| Manual zoom by points | ? | yes (2 styles) | yes | yes | yes | yes |
| Background, margins, rounded corners | yes | yes | yes | yes | yes | yes |
| GIF export | yes | yes (up to 1080p) | ? | yes | yes | yes |
| MP4 export presets | yes | yes | 4K / 60 fps | yes | yes | yes |
| Frame cropping | ? | ? | ? | yes | yes | ? |
| Keyboard keys | yes | ? | ? | ? | no | yes |
| Countdown, pause | yes | ? | pause, resume | ? | ? | ? |
| Cloud link | yes | yes (30 min) | yes | no | no | no |
| Drag the file out of the editor | yes (quick preview) | ? | ? | ? | ? | ? |
| Price | $35 once | $9/month (annual) or $29/month | free, $58 once | free (AGPL) | free (MIT, archived) | free (Apache, paused) |

Others: Shottr only does screenshots (scrolling, OCR, ruler, no recording),
pay-what-you-want around $12. ScreenFloat ($17.99 once) has cut markers placed
during recording. Loom, Tella, Zight, Descript are cloud, per user and per month.
QuickTime / Cmd+Shift+5: free, timer, clicks, draggable thumbnail, no system sound.

## Common base and differentiators

Base (almost all): area, window or full-screen capture, mic, trim, MP4 export, GIF export,
backgrounds / margins / rounded corners, visible clicks, auto zoom for the "polished demo" class.

Differentiators (one or two products): scrolling and OCR (CleanShot, Shottr, Snagit); automatic
masking of sensitive data (Xnapper, screenshots only); cut markers during
recording (ScreenFloat); activity-planned zoom (Screenize); upsampling and looping
cursor (Screen Studio); transcript-based editing (Tella, Descript); self-hosting (Cap);
local only, no account (Shottr, Xnapper, Recordly, QuickTime).

**Not found among the competitors read: combining two videos.** Not specifically searched, so to be
verified before boasting about it.

## Pricing

Free open source (Kap, Recordly, OpenScreen, Screenize, OBS, Cap free); $12 (Shottr);
$18 (ScreenFloat); $35 (CleanShot X); $58 (Cap desktop, commercial use); subscription
(Screen Studio $108/year, Snagit about 40 EUR/year); per user and per month (Loom, Tella, Zight,
Descript, $10 to $65). Screen Studio removed the lifetime license: only CleanShot ($35)
and Cap ($58) remain as one-price "polished demo" apps. The free competitors are cross-platform
Electron apps: a **native, signed, one-time-price or free** app stands out through
speed, file size, reliability and privacy, not through the number of features.

## Roadmap proposed by the study (priority, effort)

| # | Feature | Effort |
|---|---|---|
| 1 | Reliable recording core: area / window / full screen, mic and sound, countdown, pause, global shortcut, crash recovery | medium |
| 2 | "Twitter" export preset with a size budget (H.264 / AAC, 1080p or 720p, bitrate computed to stay under the limit, live size estimate); limits to be confirmed on X's official help | small |
| 3 | Auto zoom from clicks and typing, editable like points with curves | large |
| 4 | Cursor: smoothing, size after the fact, ripple on click, hiding when idle, motion blur | medium |
| 5 | Backgrounds, margins, rounded corners, shadow, presets | small |
| 6 | Drag the file out of the editor + quick thumbnail after recording | small |
| 7 | Annotations on the timeline (arrow, text, spotlight, blur with a duration) | medium |
| 8 | Combine two videos | medium |
| 9 | Frame cropping and per-segment speed | small |
| 10 | GIF export with a size cap | small |
| 11 | Cut markers placed during recording | small |
| 12 | Key display | medium |
| 13 | OCR on an image and automatic masking (emails, API keys) | medium |

Not to do (for now): cloud hosting, share links, view analytics,
team spaces; AI transcription and filler-word removal; screenshot suite
(scrolling, image annotation); Windows and Linux; live streaming and scenes (OBS); plugin
marketplace.

## Risks and unknowns

- CleanShot X 5.0 is the main threat: to be tested for real.
- Recordly and OpenScreen are moving fast and are free.
- Not verified: Screen Studio's changelog, Kap's latest release, Cap's current license and
  version, X's current limits (third-party source only).
- The accusations about Loom's prices come from competing sites: not reliable.

## Main sources

cleanshot.com (pricing, features, changelog), screen.studio, cap.so/pricing,
github.com/CapSoftware/Cap, github.com/webadderall/Recordly, github.com/siddharthvaddem/openscreen,
github.com/syi0808/screenize, github.com/wulkano/Kap, getkap.co, shottr.cc, xnapper.com,
eternalstorms.at/screenfloat, loom.com/pricing, techsmith.com (Snagit), zight.com, tella.com,
descript.com/pricing, obsproject.com, support.apple.com (capture and recording),
thesweetbits.com (CleanShot vs Shottr, Recordly), setapp.com (CleanShot vs Shottr),
producthunt.com (Cap reviews), postfa.st (X video sizes), newreleases.io (Cap v0.5.9).
