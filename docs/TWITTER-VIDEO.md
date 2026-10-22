# Twitter video constraints (and why a 2 MB video is rejected)

Real case (2026-10-20): QuickTime recording of 1280x316, 240 fps.
Rejected even though it weighed only 1.9 MB.

Causes:
- 4:1 ratio, whereas Twitter accepts from 1:3 to 3:1.
- 240 fps, whereas 60 fps is the maximum.

What the Méliès export does (default settings):
- H.264 in an MP4, `faststart` (`shouldOptimizeForNetworkUse`), AAC audio at 128 kb/s when the video has sound
- 30 fps
- max width 1920 (the export options also offer 1280, 854 and 640, labeled 720p, 480p and 360p)
- black bars added if the ratio falls outside 1:3 to 3:1 (without cropping)
- result on the case above: 1280x432, 30 fps, 129 KB

Export options (the export panel in the editor, used by copy, save, share and drag):
- Format: MP4 (H.264), HEVC (about 40% smaller, but Twitter / X and some apps may reject it) or GIF.
- Maximum size: no limit, 1, 2, 3, 5, 8, 15, 25, 50 or 100 MB, or a custom value in MB. The encoder aims at 93% of the
  limit, encodes again with a corrected bitrate (three attempts at most) if the file is still too large, and shows the real size if
  nothing fits (a GIF shrinks its width and frame rate instead).
- The panel shows a size estimate measured on a short test encode; it is a range ("Between X and Y MB") when the
  content is simple enough to stay under the bitrate ceiling. Set a maximum size for an exact result.
- Esc cancels a running export.

ffmpeg equivalent, to check:

```bash
ffmpeg -i in.mov -vf "fps=30,pad=1280:432:(ow-iw)/2:(oh-ih)/2:color=black" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart out.mp4
```
