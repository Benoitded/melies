# Méliès

Petit éditeur vidéo pour Mac, dans la barre de menu, inspiré de Shottr.
Un raccourci global ouvre l'éditeur sur ta dernière capture d'écran vidéo,
tu rognes, et tu copies ou enregistres un MP4 que Twitter accepte.

Nom : Georges Méliès, inventeur du trucage et du montage à l'écran.

## État

Outil perso, Mac uniquement (macOS 14+), Swift / SwiftUI. Pas de signature
ni de publication pour l'instant. Voir `docs/ROADMAP.md`.

## Lancer

```bash
Scripts/build.sh && open ~/Applications/Melies.app
```

Le script signe avec ton certificat "Apple Development" s'il existe, ce qui
évite que macOS redemande l'accès au Bureau à chaque build.

Ouvrir directement une vidéo : `open -a ~/Applications/Melies.app fichier.mov`.

## Docs

- `docs/DECISIONS.md` : pourquoi Swift, pourquoi ce nom, ce qu'on a écarté
- `docs/SHORTCUTS.md` : raccourcis globaux et de l'éditeur
- `docs/SHOTTR-REFERENCE.md` : ce qu'on reprend de Shottr (conventions, pas de code)
- `docs/TWITTER-VIDEO.md` : contraintes vidéo de Twitter et ce que fait l'export
- `docs/ROADMAP.md` : v1, v2, v3
