# Twitter video constraints (and why a 2 MB video is rejected)

Real case (2026-10-20): QuickTime recording of 1280x316, 240 fps.
Rejected even though it weighed only 1.9 MB.

Causes:
- 4:1 ratio, whereas Twitter accepts from 1:3 to 3:1.
- 240 fps, whereas 60 fps is the maximum.

What the Méliès export does:
- H.264 in an MP4, yuv420p, `faststart`
- 30 fps
- max width 1920
- black bars added if the ratio falls outside 1:3 to 3:1 (without cropping)
- result on the case above: 1280x432, 30 fps, 129 KB

ffmpeg equivalent, to check:

```bash
ffmpeg -i in.mov -vf "fps=30,pad=1280:432:(ow-iw)/2:(oh-ih)/2:color=black" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p -an -movflags +faststart out.mp4
```
