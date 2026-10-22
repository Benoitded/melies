# Shortcuts

## Global

| Shortcut | Action |
|---|---|
| Cmd+Shift+6 (configurable) | Start recording (you draw the region), the same shortcut stops it. During the optional countdown, it cancels |
| Cmd+Shift+E (configurable) | Open the editor on the latest video of the watched folder (the Desktop by default, Settings > General) |

While recording, everything outside the region is dimmed (and absent from the video), and a red `■ 0:07`
button appears in the menu bar: one click stops and opens the editor on the video.
Choosing the region: drag to draw, hold **Space** to move the rectangle without resizing it (like macOS and
Shottr), Esc to cancel.
If a countdown is set (Settings > General: Off, 3, 5 or 10 s, off by default), it shows in the middle of the area before
recording starts; Esc or the record shortcut cancels it.

Both global shortcuts can be changed in Settings > Hotkeys.

## Editor (Shottr style)

| Shortcut | Action |
|---|---|
| Space | Play / pause. While drawing a shape (arrow, rectangle, spotlight, blur), held: moves the shape instead of resizing it |
| I / O | Trim in / out point |
| Left / Right | Previous / next frame |
| Shift+Left / Right | 10 frames |
| Z | Animated zoom: creates a zoom (start + end), then adds a point at the playhead. Automatic zoom from clicks is a button in the zoom lane |
| V / A / T / R / S / B | Tools: select, arrow, text, rectangle, spotlight, blur |
| Delete / Backspace | Deletes the selected object (annotation or zoom point) |
| C | Crop the frame (handles, Return or C to confirm, Esc to cancel) |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+C | Export the optimized file (MP4, HEVC or GIF, per the export options) and copy it |
| Cmd+S | Export the optimized file and save it next to the original |
| Cmd+O | Open a file |
| Cmd+Shift+V | Load a video from the clipboard |
| Cmd+Plus / Cmd+Minus / Cmd+0 / Cmd+1 | Zoom the canvas in, out, 100%, fit |
| Cmd+, | Open Settings |
| Cmd+W | Close the editor |
| Esc | Cancels a running export first; otherwise leaves crop, then the current tool, then the selection, then closes |

The single-key shortcuts are read from the editor window itself, only while it is the active window and not while a
text field is being edited. Letters match the typed character, so they work on AZERTY keyboards too.

Not yet: Cmd+D to duplicate an annotation.
