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
| `get_state` | durée, fps, taille, trim, crop, zooms, annotations (avec leurs id) |
| `get_frame(time)` | image JPEG de la vidéo à cet instant, pour que le modèle voie |
| `seek(time)` | déplace la tête de lecture |
| `set_trim(start, end)` | garde la portion entre start et end |
| `set_crop(x, y, width, height)` / `clear_crop` | recadrage |
| `add_zoom(time, scale, x, y, ...)` | point de caméra (la caméra y arrive à `time`) ; ajouter un point à `scale` 1 pour revenir |
| `update_zoom(id, ...)` / `delete_zoom(id)` | |
| `add_annotation(kind, start, end, ...)` | flèche, texte, rectangle, spotlight, flou |
| `update_annotation(id, ...)` / `delete_annotation(id)` | |
| `track_annotation(id)` | l'annotation suit le contenu (attend la fin du suivi) |
| `undo` / `redo` | |
| `export(path?)` | exporte avec les réglages d'export actuels |

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
- Chaque appel d'outil est une étape d'annulation (Cmd+Z). Une erreur est renvoyée avec `isError` pour que le
  modèle la lise et corrige.
- Port modifiable avec `defaults write <bundle id> mcpPort 50000`.
- Testé en vrai (harnais sans UI + curl) : authentification, `initialize`, `tools/list`, tous les outils
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
