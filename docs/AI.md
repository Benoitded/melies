# IA dans Méliès

Idée : laisser une IA monter la vidéo (et plus tard enregistrer l'écran) à la demande, par trois chemins qui
partagent la même couche d'outils.

**Tout est optionnel** : rien ne change tant que l'utilisateur n'active pas la fonction (serveur MCP désactivé
par défaut, aucune clé, aucun réseau). Les fonctions IA ne doivent jamais être nécessaires au reste de l'app.

## Couche d'outils (fait)

`Sources/Melies/EditorTools.swift` : une façade sur `EditorModel`. Chaque outil a un nom, une description, un
schéma JSON de paramètres, et s'appelle avec un dictionnaire JSON. Elle ne connaît ni MCP ni fournisseur d'IA.

Conventions :
- Temps en secondes de la vidéo source. Coordonnées normalisées 0...1 dans l'image source (origine en haut à
  gauche), comme `Annotation` et `ZoomPoint`.
- Une erreur d'outil est un texte lisible par le modèle (« end doit être > start »), jamais un crash.
- Tout passe par les mêmes propriétés que l'UI : tout est annulable avec Cmd+Z, et un « tour » de l'IA forme
  une seule étape d'annulation (`beginUndoGroup` / `endUndoGroup`).

Outils d'édition :

| Outil | Rôle |
|---|---|
| `open_video(path?)` | ouvre un fichier (sans chemin : la dernière capture) ; refusé si la vidéo ouverte a des modifications non exportées, sauf `discard_edits` |
| `get_state` | durée, durée du résultat, fps, taille, trim, crop, audio (`kept`/`removed`/`none`), zooms, annotations (avec leurs id) |
| `get_frame(time, render?)` | JPEG de la vidéo. `render: false` : image source brute (les coordonnées des outils s'y rapportent). `render: true` : ce que l'export montrera (crop, zoom, annotations, clics) |
| `seek(time)` | déplace la tête de lecture |
| `set_trim(start, end)` | garde la portion entre start et end ; rien d'autre n'est décalé |
| `set_crop(x, y, width, height)` / `clear_crop` | recadrage |
| `add_zoom_segment(start, end, scale?, x?, y?)` | zoom plein de `start` à `end`, trajet avant et après ; c'est ce qu'on veut presque toujours |
| `add_zoom(time, scale, x, y, ...)` | un point de caméra (arrivée à `time`) ; la caméra garde la dernière valeur : ajouter un point à `scale` 1 pour revenir |
| `get_camera(time)` | échelle, centre et zone visible de la caméra à cet instant |
| `update_zoom(id, ...)` / `delete_zoom(id)` | |
| `add_annotation(kind, ...)` | flèche, texte, rectangle, spotlight, flou ; renvoie l'annotation créée |
| `update_annotation(id, ...)` / `delete_annotation(id)` | |
| `track_annotation(id)` | l'annotation suit le contenu qui bouge ou défile (attend la fin du suivi) |
| `undo` / `redo` | |
| `export(path?)` | exporte la plage rognée avec les réglages d'export de l'app ; renvoie fichier, taille, résolution, durée |

Outils d'enregistrement (à faire, branchés sur `ScreenRecorder`) :

| Outil | Rôle |
|---|---|
| `start_recording(region?, window?, audio?)` / `stop_recording` | l'éditeur s'ouvre sur le résultat |
| `get_screenshot` | l'écran, pour viser une zone ou vérifier |
| `list_windows` | cibler une fenêtre |
| `wait(seconds)` | laisser tourner pendant que l'utilisateur fait sa démo |

Hors périmètre : piloter la souris et le clavier (permission Accessibilité, beaucoup plus de risques).

## 1. Serveur MCP (fait, optionnel)

Réglages > Avancé > « Serveur MCP (IA) », désactivé par défaut. Un serveur HTTP local (`MCPServer.swift`,
protocole dans `MCPProtocol.swift`, JSON-RPC 2.0, transport « Streamable HTTP » en POST) à
`http://127.0.0.1:47821/mcp`.

- Sécurité : écoute sur la boucle locale uniquement, clé secrète obligatoire (`Authorization: Bearer <clé>`,
  ou `?token=`), `Host` et `Origin` vérifiés (une page web du navigateur ne peut pas l'atteindre). « Nouvelle
  clé » invalide les clients configurés.
- Connexion : les Réglages copient la commande Claude Code
  (`claude mcp add --transport http melies http://127.0.0.1:47821/mcp --header "Authorization: Bearer ..."`)
  ou une config JSON pour les autres clients.
- Les appels sont exécutés un par un (deux clients ne mélangent pas leurs modifications), une connexion qui n'envoie
  pas sa requête en 30 s est coupée.
- Chaque appel d'outil est une étape d'annulation (Cmd+Z). Une erreur est renvoyée avec `isError` pour que le
  modèle la lise et corrige.
- Port modifiable avec `defaults write <bundle id> mcpPort 50000`.
- Conçu avec un vrai agent : un Claude Code branché dessus a monté une vidéo (annotation, zoom, trim, export) et
  listé ses frictions ; les corrections (rendu dans `get_frame`, `add_zoom_segment`, `get_camera`, `open_video`,
  retours complets, sens du temps et des tailles écrits dans les descriptions) viennent de là.
- Testé en vrai (harnais sans UI + curl + Claude Code) : authentification, `initialize`, `tools/list`, tous les outils
  d'édition, erreurs de validation, annulation, suivi, export.

## 2. Chat dans l'éditeur (après)

Un bouton dans `TopBar` ouvre un panneau à droite : fil de messages, champ de saisie, bouton stop.
- Clé API (Anthropic d'abord, OpenAI ensuite) dans le Keychain, fournisseur et modèle dans les Réglages.
- Boucle d'agent : message + état + frames, le modèle répond par des appels d'outils, jusqu'à la fin.
- Chaque action s'affiche dans le fil (« Zoom ajouté à 0:12 »). Un tour = un Cmd+Z.
- Une clé API n'est pas un abonnement ChatGPT/Claude : il faut une vraie clé.

## Garde-fous (valables pour les deux)

- Enregistrement lancé par l'IA : l'overlay reste visible, un toast annonce le début, durée maximale par défaut
  (5 min), Esc et le bouton stop coupent toujours. Confirmation avant chaque `start_recording`, avec une option
  « toujours autoriser » dans les réglages.
- Vie privée : les frames et screenshots partent chez le fournisseur (chat) ou le client MCP. Mention au
  premier usage, résolution réduite, possibilité de ne capturer qu'une fenêtre.
- MCP : localhost uniquement, token obligatoire, désactivé par défaut.
