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

## Liquid Glass partout où ça flotte (2026-10-22)

Minimum macOS 26, sans code de secours : outil perso sur un Mac en macOS 27. Le verre sert aux
surfaces qui flottent au-dessus du contenu, jamais au contenu lui-même : les trois capsules de la
barre d'outils (`GlassEffectContainer`), le panneau des réglages d'outil, les infobulles, la
bulle "Copié", le bouton lecture et les boutons de l'écran vide (`.buttonStyle(.glass)`), le
bouton principal de l'accueil (`.glassProminent`). La timeline, la piste de zoom et la vidéo
restent du contenu. Les Réglages utilisent le style toolbar natif d'AppKit.

Piège : le rendu hors écran (`cacheDisplay`) ne dessine pas le verre. Pour juger l'apparence, il
faut capturer la vraie fenêtre (l'app doit être lancée avec sa fenêtre ouverte pour être
ciblable par l'outil de capture).

## Annotations : un seul dessin pour l'aperçu et l'export (2026-10-22)

Flèche, texte et rectangle sont des objets avec une durée (début, fin) et une géométrie normalisée
dans l'image source : ils suivent donc le recadrage et les zooms animés. `AnnotationRenderer` les
dessine en Core Graphics dans l'espace des pixels source ; l'aperçu (Canvas SwiftUI) et l'export
(compositeur Core Image) appliquent seulement une transformation différente. Les réglages (couleur,
épaisseur ou taille, style, police) sont mémorisés par type d'objet.

Piège : les raccourcis à une touche (A, T, R...) sont des boutons cachés ; ils sont désactivés
pendant la saisie de texte (`isEditingText`), sinon taper "a" lancerait l'outil flèche.

## Accueil en vrai Liquid Glass, icône en couches (2026-10-22)

L'accueil est une fenêtre `NSGlassEffectView` : le contenu reste plat dessus (pas de verre sur
du verre). L'icône est un fichier Icon Composer `Resources/Melies.icon` (fond dégradé, pellicule,
bouton lecture en verre) compilé par `actool` en `Assets.car` plus un `.icns` de secours.

## Annuler / rétablir par séquences (2026-10-22)

Un instantané de l'état éditable (annotations, points de zoom, recadrage, début et fin du trim) est
empilé au premier changement d'une séquence. Les changements espacés de moins de 0,6 s forment une
même séquence, donc un glissé, un curseur ou une frappe = une seule étape. Pas d'enregistrement à
chaque geste dans le code : un `didSet` sur ces cinq propriétés suffit. La navigation (tête de
lecture, sélection, zoom du canvas) n'est pas dans l'historique. Pendant la saisie d'un texte,
Cmd+Z appartient au champ de texte.

## Leçons du test à la souris (2026-10-22)

- Une annotation créée sous la tête de lecture à son tout début était invisible (fondu d'entrée à
  0). L'éditeur affiche maintenant les objets pleinement quand la lecture est en pause.
- Le champ de texte n'était pas actif juste après la création d'un texte : les lettres tapées
  déclenchaient des raccourcis (I, O, A, V...). Le focus est pris à l'apparition du panneau.

## Combiner deux vidéos : un fichier, puis l'éditeur (2026-10-22)

Choix : « Combiner » produit un nouveau MP4 (côte à côte, empilées ou en incrustation) qui
s'ouvre ensuite dans l'éditeur, plutôt que de rendre tout l'éditeur multi-pistes. Raison : le
recadrage, les zooms, les annotations et le trim restent écrits pour une seule vidéo ; la
combinaison est une étape en amont, simple à comprendre. Compromis : un encodage de plus (qualité
maximale pour limiter la perte).

Le compositeur (`ComposeCompositor`) dessine les deux vidéos avec la même géométrie que l'aperçu
de la fenêtre (`ComposeGeometry`). Quand une vidéo finit avant l'autre, sa dernière image reste
affichée. L'incrustation a des coins arrondis, un liseré et une ombre. Le son des deux vidéos est
conservé s'il existe.

## Spotlight et flou (2026-10-22)

Le spotlight assombrit tout sauf une zone (dessiné comme les autres annotations). Le flou et la
pixelisation changent les pixels de la vidéo : ils sont appliqués sur l'image source avant le
recadrage et la caméra, donc le motif suit le zoom. L'aperçu lit la dernière image décodée du lecteur
(`AVPlayerItemVideoOutput`) et utilise le même filtre que l'export. Pixelisation par défaut : un flou
léger peut parfois se défaire, des gros blocs non.

## Poignée de glisser-déposer (2026-10-22)

La poignée de la barre d'outils (page vide entre deux groupes de points, comme Shottr) fournit le MP4
optimisé quand l'app de destination le demande : `NSItemProvider` avec une représentation de fichier
paresseuse (comme une promesse de fichier). L'export ne se fait donc qu'au dépôt, pas à chaque
modification. Le glisser n'enregistre ni ne ferme rien : c'est un geste de partage, pas une sortie.
## Audio (2026-10-22)

Le son du système (`capturesAudio`) et le micro (`captureMicrophone`, macOS 15) passent par
ScreenCaptureKit et sont écrits dans le même fichier par `SCRecordingOutput`. Les deux options sont
désactivées par défaut (respect de la vie privée), réglables dans les Réglages et dans le menu de
la barre de menu. Le micro demande l'autorisation la première fois ; refusé, l'enregistrement continue
sans la voix et une bulle le dit.

Un enregistrement peut avoir plusieurs pistes audio : l'export les mélange en une seule piste
(`AVMutableAudioMix`), ou les met à zéro si le bouton son de l'éditeur est coupé. Piège de test :
lancée directement depuis un terminal, l'app n'hérite pas de l'autorisation d'enregistrement d'écran
(macOS l'attribue au programme parent) ; il faut la démarrer par `open -a` pour tester la capture.

## Clics visibles (2026-10-22)

Les clics sont enregistrés à côté de la position du curseur (`<nom>.cursor.json` devient un objet
`{cursor, clicks}` ; l'ancien tableau simple se lit toujours). On ne dessine pas dans la vidéo
d'origine : l'anneau est calculé au rendu, donc on peut l'allumer, l'éteindre, changer sa couleur et
sa taille après coup, et il suit le recadrage et les zooms. Seuls les clics dans la zone enregistrée
comptent. Le curseur lissé n'est pas fait : il faudrait enregistrer sans le vrai curseur et le
redessiner, ce qui perd les formes (flèche, barre de texte, main).
