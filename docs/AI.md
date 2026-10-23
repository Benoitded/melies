# AI in Melies

Idea: let an AI edit the video (and record the screen for a demo) on request, through three paths that
share the same tool layer.

**Everything is optional**: nothing changes until the user enables the feature (MCP server off
by default, no key, no network). AI features must never be required for the rest of the app.

## Tool layer (done)

`Sources/Melies/EditorTools.swift`: a facade over `EditorModel`. Each tool has a name, a description, a
JSON schema of parameters, and is called with a JSON dictionary. It knows neither MCP nor any AI provider.

Conventions:
- Times in seconds of the source video. Coordinates normalized 0...1 in the source image (origin at top
  left), like `Annotation` and `ZoomPoint`.
- A tool error is a model-readable text ("end must be > start"), never a crash.
- Everything goes through the same properties as the UI: everything can be undone with Cmd+Z, and one AI "turn" forms
  a single undo step (`beginUndoGroup` / `endUndoGroup`).

Editing tools:

| Tool | Role |
|---|---|
| `open_video(path?)` | opens a file (without a path: the last capture); refused if the open video has unexported edits, unless `discard_edits` |
| `get_state` | duration, result duration, fps, size, trim, crop, audio (`kept`/`removed`/`none`), zooms, annotations (with their ids) |
| `get_frame(time, render?)` | JPEG of the video. `render: false`: raw source image (tool coordinates refer to it). `render: true`: what the export will show (crop, zoom, annotations, clicks) |
| `seek(time)` | moves the playhead |
| `set_trim(start, end)` | keeps the portion between start and end; nothing else is shifted |
| `set_crop(x, y, width, height)` / `clear_crop` | crop |
| `add_zoom_segment(start, end, scale?, x?, y?)` | full zoom from `start` to `end`, with travel before and after; this is what you want almost every time |
| `add_zoom(time, scale, x, y, ...)` | one camera point (arrival at `time`); the camera keeps the last value: add a point at `scale` 1 to go back |
| `get_camera(time)` | scale, center and visible area of the camera at that instant |
| `update_zoom(id, ...)` / `delete_zoom(id)` | |
| `add_annotation(kind, ...)` | arrow, text, rectangle, spotlight, blur; returns the created annotation |
| `update_annotation(id, ...)` / `delete_annotation(id)` | moving an annotation clears its tracking |
| `track_annotation(id, from?)` | the annotation follows moving or scrolling content from `from` (default: its start) to its end, and ends early if the content leaves the frame or is covered (waits for tracking to finish) |
| `undo` / `redo` | |
| `export(path?)` | exports the trimmed range with the app's export settings (format, maximum size, resolution); returns file, size, resolution, duration. See the path rules below |

Export path rules (the path comes from an AI client, so it is untrusted):
- Without `path`, the file is saved next to the original as `name-optimized.<ext>`.
- The extension is forced to the one of the current export format (`mp4` or `gif`), whatever the client asks.
- The folder must be under `~/Movies`, `~/Desktop`, `~/Documents`, `~/Downloads` or `~/Pictures`, or be the watched
  folder, the folder of the open video or the temporary folder (symbolic links are resolved first). Hidden folders and
  anything inside an `.app` are refused.
- An existing file is never overwritten: a free name `-2`, `-3`... is used instead.

Recording tools (done, same MCP server; logic in `RecordingControl.swift`, real screen parts in `RecordingLive.swift`):

| Tool | Role |
|---|---|
| `get_screen_layout` | displays (id, name, frame in points, scale, `has_mouse`) and visible windows (id, app name, bounds, display). No window titles, no Melies windows. Marked as untrusted data |
| `start_recording(display?, x, y, width, height \| window, audio?, max_seconds?, countdown?)` | records a region (points, relative to the top left of the display) or a window (its bounds plus an 8 pt margin, clamped to the display). `audio`: `none` (default), `microphone`, `system`, `both`. `max_seconds`: 1 to 600, default 120. `countdown`: 0 to 10 s, default 0 |
| `stop_recording` | stops; the editor opens on the file; returns `file`, `duration_seconds`, `has_clicks` / `auto_zoom_available`, `stopped_by` (`client`, `time_limit`, `user`). Also returns a recording that already ended by itself |
| `get_recording_status` | `idle`, `waiting_for_user_confirmation`, `recording` (elapsed, region, audio) or `stopping` |

Intended flow, only when the user explicitly asked to record: `get_screen_layout`, `start_recording`, do the demo with
the client's own tools (Melies does not drive the mouse or keyboard), `stop_recording`, then `get_state` and edit
(`add_zoom_segment`, `add_annotation`, `set_trim`...) and `export`.

Safety model (this is the user's screen):
- Every `start_recording` shows a native dialog naming the client and the region, with Allow and Deny only. Return
  means Deny, there is no "always allow", and it denies by itself after 30 s. The text says the AI app will see the
  recording. Nothing is captured before a click on Allow. Names shown in it are stripped of control characters and
  shortened, so a client or an app cannot fake extra lines.
- Validation happens before the dialog: region at least 40 x 40 points and inside the display, one recording at a
  time (a recording started by the user counts), refused while an export runs.
- The red menu bar timer and the dimming overlay stay, the shortcut and the red button stop it. It stops by itself at
  `max_seconds` (default 120, never more than 600). Melies windows are never in the video.
- Needs the Screen Recording permission like any recording; without it the call fails with a clear error. Microphone
  access is asked on first use when `audio` includes the microphone.
- Everything stays behind the existing MCP checks (off by default, loopback, key, Host and Origin). No network access
  was added. The AI activity badge shows during these tools like during the others.
- `get_screen_layout` text (app names) is untrusted: the tool descriptions and the server instructions say so.

Out of scope: driving the mouse and keyboard (Accessibility permission, far more risk).

## 1. MCP server (done, optional)

Settings > Advanced > "MCP server (AI)", off by default. A local HTTP server (`MCPServer.swift`,
protocol in `MCPProtocol.swift`, JSON-RPC 2.0, "Streamable HTTP" transport over POST) at
`http://127.0.0.1:47821/mcp`.

- Security: listens on the loopback interface only, secret key required (`Authorization: Bearer <key>`,
  or `?token=`), `Host` must be `127.0.0.1` or `localhost`, and `Origin`, when present, must have exactly that host
  (a browser web page cannot reach it). Request bodies are limited to 1 MB, at most 8 connections are open at once.
  "New key" invalidates configured clients.
- The key is stored in the macOS Keychain (readable only while the Mac is unlocked, never synced), not in the
  preferences file. A key left in the preferences by an older version is moved to the Keychain.
- Connection: Settings copies the Claude Code command
  (`claude mcp add --transport http melies http://127.0.0.1:47821/mcp --header "Authorization: Bearer ..."`),
  a URL with the key (for apps that cannot send a header) or a JSON config for other clients.
  The copied command and URL contain the key in clear text, so a shell may keep them in its history and a client may
  log the URL. Prefer the `Authorization` header form: paste the copied command only in a shell with history off, or
  replace the literal key by an environment variable you set from a file (`--header "Authorization: Bearer $MELIES_MCP_KEY"`),
  and keep the key out of files you commit. Use the `?token=` URL only for a client that cannot send a header (the key can
  then appear in that client's logs). If a key leaks, "New key" rotates it and invalidates every configured client.
- Feedback (Settings > Advanced > MCP server): a status line (waiting for an AI app, connected with the client name,
  "working" with the tool in progress, last action and when, a red message when an app used a wrong key), and a
  three-step checklist (copy the command, paste it in a terminal, ask for an edit). While an AI app edits, the editor
  shows a badge at the top ("<app> is editing...", then "is done") with the name of the tool.
- Calls run one at a time (two clients do not mix their edits), a connection that does not send
  its request within 30 s is cut, and a single call that runs longer than 120 s has its tracking and export cancelled
  so that it returns.
- Each tool call is an undo step (Cmd+Z). An error is returned with `isError` so that the
  model reads it and corrects itself.
- Port can be changed with `defaults write <bundle id> mcpPort 50000`.
- Designed with a real agent: a Claude Code connected to it edited a video (annotation, zoom, trim, export) and
  listed its frictions; the fixes (rendering in `get_frame`, `add_zoom_segment`, `get_camera`, `open_video`,
  complete returns, direction of time and sizes written in the descriptions) come from there.
- Tested for real (UI-less harness + curl + Claude Code): authentication, `initialize`, `tools/list`, all the
  editing tools, validation errors, undo, tracking, export. Unit tests (`swift test`) cover the export path rules,
  HTTP request parsing limits and JSON-RPC error handling (`Tests/MeliesTests/SafetyTests.swift`).
- The `MELIES_*` test hooks are compiled only into debug builds (or with `MELIES_HOOKS=1 Scripts/build.sh`): a
  release build has none, so no environment variable can change what the published app does.

## 2. Chat in the editor (later)

A button in `TopBar` opens a panel on the right: message thread, input field, stop button.
- API key (Anthropic first, OpenAI next) in the Keychain, provider and model in Settings.
- Agent loop: message + state + frames, the model replies with tool calls, until done.
- Each action is shown in the thread ("Zoom added at 0:12"). One turn = one Cmd+Z.
- An API key is not a ChatGPT/Claude subscription: a real key is required.

## Guardrails (apply to both)

- Recording started by the AI: the overlay and the red timer stay visible, default maximum duration 2 min (600 s at
  most), the red button and the shortcut always cut it. Confirmation before each `start_recording`, with no
  "always allow" option (see the safety model above).
- Privacy: frames and screenshots go to the provider (chat) or to the MCP client. Notice on
  first use, reduced resolution, option to capture only one window.
- MCP: localhost only, token required (kept in the Keychain), off by default, export limited to safe folders and never
  overwriting a file.
