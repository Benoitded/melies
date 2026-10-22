# AI in Méliès

Idea: let an AI edit the video (and later record the screen) on request, through three paths that
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

Recording tools (to do, wired to `ScreenRecorder`):

| Tool | Role |
|---|---|
| `start_recording(region?, window?, audio?)` / `stop_recording` | the editor opens on the result |
| `get_screenshot` | the screen, to target an area or verify |
| `list_windows` | target a window |
| `wait(seconds)` | let it run while the user does their demo |

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

- Recording started by the AI: the overlay stays visible, a toast announces the start, default maximum duration
  (5 min), Esc and the stop button always cut it. Confirmation before each `start_recording`, with an
  "always allow" option in the settings.
- Privacy: frames and screenshots go to the provider (chat) or to the MCP client. Notice on
  first use, reduced resolution, option to capture only one window.
- MCP: localhost only, token required (kept in the Keychain), off by default, export limited to safe folders and never
  overwriting a file.
