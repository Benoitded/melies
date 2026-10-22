# Concurrents : synthèse et feuille de route (2026-10-22)

Trois études, résumées ici, avec leurs détails dans `docs/research/` :
- `blogs-and-reviews.md` : pages éditeur, comparatifs, matrice des fonctions et des prix ;
- `forums.md` : avis d'utilisateurs (Hacker News, Product Hunt, Setapp, forum de retours de Screen Studio) ;
- `github-issues.md` : tickets des dépôts publics (Cap, Kap, Recordly, OpenScreen, Screenize, trois apps Swift).

**Limites communes :** Reddit n'a pas pu être lu (outils refusés) ; X et Bluesky non plus ; beaucoup de
sources sont des pages de concurrents ; les comptes de tickets viennent des titres seulement. Les
conclusions sont des indices solides, pas des statistiques.

## Ce que disent les trois études ensemble

| Constat | Forums | Tickets GitHub | Blogs et prix |
|---|---|---|---|
| **La fiabilité compte plus que le nombre de fonctions** | n°2 des qualités citées | plantages, exports cassés, régressions à chaque version | CleanShot X 5.0 casse après mise à jour (avis Setapp) |
| **L'export doit être fiable et identique à l'aperçu** | exports lourds ou illisibles | première catégorie de bugs de tous les dépôts | n/a |
| **L'audio est le premier sujet de bugs** | demandé partout | micro absent, dérive, pause qui corrompt | présent chez presque tous |
| **Export à taille cible** | demandé à Screen Studio, **refusé** | demandé chez Kap, OpenScreen, Cap | seulement des préréglages génériques |
| **Prix honnête, pas d'abonnement** | n°1 des qualités citées | n/a | Screen Studio a supprimé l'achat unique |
| **Confiance macOS (signature, autorisations)** | n/a | « malware », app supprimée, boucles d'autorisation | n/a |
| **Zoom auto, curseur, clics** | souhaité, avec zoom désactivable | les bugs, pas l'idée (double curseur, retard) | CleanShot X 5.0 vient de l'ajouter |
| **Local d'abord, sans compte** | demandé | le cloud de Cap = 130 tickets, surtout du bruit | différenciateur de Shottr, Xnapper, Recordly |
| **Annotations avec durée dans la vidéo** | demandé (CleanShot) | flou « fonction de base » | peu de concurrents le font bien |

**Menace principale :** CleanShot X 5.0 (septembre 2026) entre dans l'espace de Méliès (mode Studio,
zooms intelligents, lissage du curseur, fonds). À essayer en vrai avant de décider.

## Où en est Méliès

| Fonction attendue | État |
|---|---|
| Zone, trim, recadrage, annulation | fait |
| Zoom animé (points, vitesse, styles), centrage sur le curseur | fait |
| Annotations avec durée : flèche, texte, rectangle, spotlight, flou | fait |
| Clics visibles | fait |
| Micro et son du système, son coupé ou gardé à l'export | fait (micro à tester) |
| Combiner deux vidéos | fait (rare chez les concurrents lus, non cherché précisément) |
| Poignée de glisser-déposer du fichier | fait (le dépôt reste à essayer) |
| Export à taille cible, GIF | moteur fait et testé en ligne de commande, interface à faire |
| Export identique à l'aperçu | par construction (même dessin), à tester sur des cas réels |
| Zoom auto à partir des clics | à faire (les clics sont enregistrés) |
| Fond, marges, coins arrondis, ombre | à faire |
| Webcam en incrustation | à faire |
| Compte à rebours, pause, fenêtre ou plein écran | à faire |
| Suivi d'objet pour flou et flèches | demandé, à faire (Vision) |
| Affichage des touches | à faire, sans jamais stocker le texte saisi |
| Signature développeur et notarisation | à faire avant toute distribution |
| Captures d'écran fixes (défilante, OCR) | hors périmètre pour l'instant |

## Feuille de route proposée

1. **Export à taille cible et GIF** (interface, estimation de taille, préréglage Twitter) : en cours.
2. **Fiabilité de l'enregistrement et de l'export** : récupération du dernier enregistrement après un
   plantage, progression et annulation de l'export, test de longs enregistrements (10 min et plus) avec
   audio, test à chaque version de macOS.
3. **Zoom auto à partir des clics**, modifiable comme les points de zoom actuels.
4. **Fond, marges, coins arrondis, ombre**, avec préréglages.
5. **Suivi d'objet** pour le flou, le spotlight, le rectangle, le texte et les flèches.
6. **Choix de la cible** : fenêtre, plein écran, zone mémorisée ; compte à rebours et pause.
7. **Confiance macOS** : signature, notarisation, mise à jour automatique, Homebrew.
8. Webcam en incrustation ; affichage des touches.

## À ne pas faire

Cloud, comptes, liens de partage, analyses de visionnage, transcription par IA, place de marché de
plugins, abonnement seul, fonctions qui disparaissent pour les acheteurs, Electron.

## Prix (à décider plus tard)

Les trois études convergent : achat unique avec un an de mises à jour et renouvellement facultatif,
jamais d'abonnement seul. Repères : Shottr environ 12 $, ScreenFloat 18 $, CleanShot X 35 $, Cap 58 $,
Screen Studio 108 $ par an.
