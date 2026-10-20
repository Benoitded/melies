# Contraintes vidéo Twitter (et pourquoi une vidéo de 2 Mo est refusée)

Cas réel (2026-10-20) : enregistrement QuickTime de 1280x316, 240 fps.
Refusé alors qu'il ne pesait que 1,9 Mo.

Causes :
- Ratio 4:1, alors que Twitter accepte de 1:3 à 3:1.
- 240 fps, alors que 60 fps est le maximum.

Ce que fait l'export Méliès :
- H.264 dans un MP4, yuv420p, `faststart`
- 30 fps
- largeur max 1920
- bandes noires ajoutées si le ratio sort de 1:3 à 3:1 (sans rogner)
- résultat sur le cas ci-dessus : 1280x432, 30 fps, 129 Ko

Équivalent ffmpeg, pour vérifier :

```bash
ffmpeg -i in.mov -vf "fps=30,pad=1280:432:(ow-iw)/2:(oh-ih)/2:color=black" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p -an -movflags +faststart out.mp4
```
