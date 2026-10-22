# Méliès

Enregistreur d'écran et petit éditeur vidéo pour Mac, dans la barre de menu, inspiré de Shottr.
Un raccourci global filme une zone de l'écran, l'éditeur s'ouvre directement dessus, tu rognes,
tu annotes, et tu copies ou glisses un MP4 (ou un GIF) léger vers n'importe quelle app, par exemple Twitter / X.

Gratuit, local (rien ne quitte ton Mac), Mac uniquement. Nom : Georges Méliès, inventeur du trucage et du
montage à l'écran.

## Installer

1. Télécharge le dernier `Melies-X.Y.Z.dmg` depuis les [Releases](https://github.com/Benoitded/melies/releases).
2. Ouvre le DMG et glisse **Méliès** dans le dossier **Applications**.
3. Lance Méliès : une icône de pellicule apparaît dans la barre de menu.
4. Au premier lancement, autorise l'**enregistrement d'écran** (Réglages Système > Confidentialité et
   sécurité) quand l'app te guide ; macOS demande parfois de relancer l'app une fois.
   Le **micro** n'est demandé que si tu l'actives pour un enregistrement.

Prérequis : **macOS 26 (Tahoe) ou plus récent**. L'app est signée et notarisée par Apple. Les mises à jour
arrivent toutes seules (menu de la barre de menu > « Rechercher des mises à jour… », ou Réglages > Avancé).

## Premiers pas

| Raccourci | Action |
|---|---|
| ⌘⇧6 | Dessiner la zone et lancer l'enregistrement ; le même raccourci l'arrête (réglable) |
| ⌘⇧E | Rouvrir l'éditeur sur le dernier enregistrement (réglable) |
| ⌘C / ⌘S | Copier / enregistrer le MP4 optimisé |

La liste complète des raccourcis est dans [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md).

## Ce que fait l'éditeur

- **Rogner** la durée (I / O) et **recadrer** l'image (C).
- **Zooms animés** (Z), placés tout seuls sur les clics enregistrés si tu veux, avec vitesse et style réglables.
- **Annotations** : flèche, texte, rectangle, spotlight, flou ou pixelisation, avec **suivi d'objet** (le flou
  accompagne un texte qui défile).
- **Clics visibles**, son du **système** et **micro**.
- **Combiner deux vidéos** : côte à côte, empilées ou en incrustation.
- **Export à taille cible** : MP4 (H.264), HEVC plus compact, ou GIF ; de 360p à 1080p ; limite de taille au
  choix (1 Mo et plus) pour passer sous les limites de Twitter / X, Slack, etc.
- **Poignée de glisser-déposer** : tire le résultat vers une conversation, un mail ou un navigateur.
- Interface Liquid Glass en **français, anglais, italien et espagnol**.

## Dépannage

- *L'enregistrement ne démarre pas* : vérifie Réglages Système > Confidentialité et sécurité >
  Enregistrement d'écran et audio système, puis relance l'app.
- *Pas de son micro* : active le micro dans le menu de la barre de menu avant d'enregistrer, et accepte la demande.
- *L'app est bloquée à l'ouverture* : clic droit sur Méliès > Ouvrir (cas d'une copie non notarisée).

## Compiler soi-même

```bash
git clone https://github.com/Benoitded/melies && cd melies
Scripts/build.sh && open ~/Applications/Melies.app
```

Il faut Xcode 26 ou plus récent. Le script signe avec ton certificat « Apple Development » s'il existe, ce
qui évite que macOS redemande les autorisations à chaque build. Pour publier une version :
[`docs/RELEASING.md`](docs/RELEASING.md).

## Docs

- [`docs/DECISIONS.md`](docs/DECISIONS.md) : pourquoi Swift, ce qu'on a écarté, comment marchent le suivi et l'export
- [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md) : raccourcis globaux et de l'éditeur
- [`docs/ROADMAP.md`](docs/ROADMAP.md) : ce qui est fait et ce qui vient
- [`docs/COMPETITORS.md`](docs/COMPETITORS.md) : étude des autres outils
- [`docs/TWITTER-VIDEO.md`](docs/TWITTER-VIDEO.md) : contraintes vidéo de Twitter / X et ce que fait l'export
- [`docs/RELEASING.md`](docs/RELEASING.md) : publier une version et les mises à jour

## Licence

À choisir avant de rendre le dépôt public (voir `docs/ROADMAP.md`).
