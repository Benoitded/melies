# Décisions

## Mac uniquement, Swift / SwiftUI (2026-10-20)

Choix : app native Swift + SwiftUI + AVFoundation, dans la barre de menu.

Pourquoi :
- Outil perso Mac, pas besoin du multiplateforme ni d'une version web.
- Barre de menu, raccourci global, presse-papiers (copier un fichier vidéo),
  encodage H.264 matériel et design système (Liquid Glass) sont natifs.
- Plus tard, ScreenCaptureKit permettra d'enregistrer l'écran nativement.

Écarté : Tauri + WebCodecs. Testé en spike : le serveur Vite a planté sous
Node 20.17 (Vite 8 demande Node 20.19+ ou 22+), et l'encodage dans un webview
restait à prouver. Tout le code Tauri a été supprimé, rien n'en est conservé.

Écarté : page web locale avec ffmpeg. Ne peut pas avoir de raccourci global.

## Nom : Méliès (2026-10-20)

Georges Méliès a inventé le jump cut, la surimpression et le trucage à
l'écran : exactement ce que fait l'outil (couper, superposer, zoomer).
Nom de commande et de dossier : `melies`, sans accent.

Écartés : `clipr` (trop de produits homonymes : téléchargeur Twitch, plateforme
UGC, gestionnaire de presse-papiers), `motionr` (libre mais sans âme).
Vérifié sur npm, Homebrew, GitHub uniquement. Marques et App Store non vérifiés.

## Raccourcis globaux : bibliothèque KeyboardShortcuts

Shottr utilise lui-même `sindresorhus/KeyboardShortcuts` (visible dans son
bundle). On fait pareil : raccourci réglable dans les Réglages.

## Signature

Compte Apple Developer disponible, mais on ne signe pas au début : build local,
signé avec l'identité de développement du Mac si présente, sinon ad hoc.
Notarisation à faire seulement si on distribue.

## Open source

Prévu plus tard, sous le GitHub de l'équipe. Mac uniquement (comme Shottr).
Avant de publier : vérifier le nom (marques, App Store), ajouter une licence,
ne rien mettre de propre à Byzantine dans le code.

## Enregistrement d'écran intégré (2026-10-20)

Demandé dès la v1 : Cmd+Shift+6 démarre et arrête. Implémentation avec
ScreenCaptureKit (`SCRecordingOutput`, macOS 15 minimum), zone dessinée sur un
overlay plein écran, fichier .mov H.264 60 fps dans le dossier surveillé, puis
l'éditeur s'ouvre dessus. L'arrêt se fait avec le même raccourci ou le bouton
rouge dans la barre de menu. Demande l'autorisation "Enregistrement de l'écran"
au premier lancement.

## Zooms animés et compositeur vidéo maison (2026-10-20)

Les zooms sont des points de caméra (temps, niveau, centre, durée de trajet, style)
rangés sur une piste sous la timeline. Z crée un zoom avec un début et une fin, puis
ajoute des points intermédiaires qui reprennent l'état courant de la caméra. Le
niveau est interpolé en échelle logarithmique, le centre linéairement, avec un style
au choix (fluide, vif, linéaire, ressort).

L'export n'utilise plus d'instructions AVFoundation à transformation constante : un
`AVVideoCompositing` maison (Core Image) calcule chaque image : rotation, recadrage,
caméra, mise à l'échelle et bandes noires. Les flèches, le texte et les rectangles seront
dessinés au même endroit, donc l'aperçu et l'export concordent. Vérifié avec une mire
fixe : image pleine identique (49 dB), zoom x2 à la bonne région.

Pendant l'enregistrement, la position du curseur est échantillonnée à 30 Hz et écrite dans
`<nom>.cursor.json` à côté de la vidéo. Un nouveau zoom se centre sur la souris à cet instant.

## Réglages des outils : panneau flottant (2026-10-20)

Inspiré de Shottr, observé directement dans l'app : quand un objet est sélectionné, un petit
panneau flottant apparaît en haut à droite de l'image (chevron pour le replier, couleur,
épaisseur en curseur en forme de coin, styles en boutons d'icônes). Même composant
(`ToolPanel`, `IconSegments`, `WedgeSlider`) pour les points de zoom maintenant, et pour les
flèches, le texte et les rectangles ensuite. La piste de zoom trace la courbe du niveau
de zoom pour qu'on voie la dynamique d'un coup d'oeil.
