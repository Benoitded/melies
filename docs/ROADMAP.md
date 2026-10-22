# Roadmap

## v1 (fait)
- [x] Enregistrement d'écran natif (ScreenCaptureKit, zone au choix) avec Cmd+Shift+6
- [x] Bouton rouge d'arrêt dans la barre de menu, ouverture auto de l'éditeur
- [x] App barre de menu avec icône, menu, Réglages et liste des raccourcis
- [x] Raccourci global qui ouvre l'éditeur sur la dernière vidéo du Bureau
- [x] Trim (I / O) avec lecture en boucle
- [x] Export Twitter : Cmd+C (copier le fichier), Cmd+S (enregistrer)
- [x] Glisser-déposer, Cmd+Shift+O, Cmd+Shift+V

## v2
- [x] Crop de l'image (poignées, appliqué à l'export)
- [x] Aperçu des images sur la timeline, quadrillage derrière la vidéo
- [x] Réglages à onglets (Général, Raccourcis, Avancé), thème clair / sombre / système
- [x] Flèches, texte, rectangle (panneau de réglages, durée sur la timeline)
- [x] Spotlight (zone éclairée), flou et pixelisation
- [x] Clics visibles : anneau qui s'étend à chaque clic enregistré (couleur et taille réglables)
- [x] Export à taille cible (MP4, GIF), résolution, estimation de taille ; copier, enregistrer, partager et glisser suivent ces réglages
- [x] Export plus compact : tailles de 1 à 100 Mo (ou libre), 360p à 1080p, HEVC
- [x] Suivi d'objet : flou, spot, rectangle, texte, flèche suivent le contenu (défilement, déplacement) et s'arrêtent quand il disparaît
- [ ] Priorités issues de l'étude des concurrents : voir `docs/COMPETITORS.md`
- [x] Zooms animés : points de caméra (niveau, vitesse, style), centrage auto sur le curseur enregistré, aperçu et export identiques
- [x] Cmd+Z / Cmd+Shift+Z (annuler / rétablir : annotations, zooms, recadrage, trim)

## v3
- [x] Poignée de glisser-déposer : le MP4 optimisé se dépose dans n'importe quelle app
- [x] Deux vidéos côte à côte, empilées, ou en incrustation (fenêtre « Combiner », résultat rouvert dans l'éditeur)
- [x] Audio : son du système et micro pendant l'enregistrement, son gardé ou coupé à l'export
- [x] Zoom auto depuis les clics enregistrés (bouton dans la piste de zoom)

## IA (voir `docs/AI.md`)
- [x] Couche d'outils d'édition (façade JSON sur `EditorModel`)
- [x] Serveur MCP local (optionnel, désactivé par défaut)
- [ ] Outils d'enregistrement d'écran
- [ ] Panneau de chat avec clé API

## Plus tard
- [ ] Distribution : hardened runtime, signature Developer ID, notarisation, DMG, GitHub Releases
- [ ] Mise à jour automatique (Sparkle, flux signé sur GitHub Releases)
- [ ] CI GitHub Actions (build + tests)
- [ ] Open source : vérifier le nom, choisir une licence, README avec GIF de démo
