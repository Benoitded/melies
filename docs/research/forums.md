# Concurrents : ce que disent les utilisateurs (forums et avis, 2026-10-22)

Rapport d'un sous-agent de recherche, relu et condensé.

## Limites à connaître

- **Reddit n'a pas pu être lu** (les outils de lecture sont refusés). Tout ce qui est étiqueté Reddit
  vient de seconde main (un blog concurrent ou AlternativeTo qui le cite). X et Bluesky : non joignables.
- Lu pour de vrai : Hacker News (environ 5 fils lus en détail), avis Product Hunt de Cap (8 avis,
  3,9 sur 5), avis Setapp de CleanShot X (environ 10), le forum de retours de Screen Studio, les
  actualités d'AlternativeTo.
- Échantillon petit : « N sources » veut dire « N sources qui le mentionnent », pas une statistique.
  Les commentateurs de Hacker News sont plutôt développeurs et sensibles au prix.

## Par produit

| Produit | Ce qui plaît | Ce dont on se plaint | Pourquoi on part |
|---|---|---|---|
| Screen Studio | démos soignées, curseur lissé, zoom auto ; « vaut le coup » quand c'était un achat unique avec un an de mises à jour | licence à vie à 89 $, puis 229 $ (plus 109 $ par an), puis **abonnement seul** (9 $/mois en annuel, 29 $/mois en mensuel) ; plantages ; Mac seulement ; vidéos qui ne se lisent pas dans Safari ; demandes : rognage fiable, vitesse, taille du curseur, flèches, zoom désactivable, flou qui suit le contenu | le changement d'abonnement ; ils citent Cap, Screenity, Canvid, OpenScreen, OBS |
| CleanShot X | tout-en-un, facile, défilante, enregistrement quotidien | **casse après les mises à jour** (lent sur Intel après la 5.0.1, ne se charge pas sur macOS 27), qualité des GIF, fonctions cachées, un avis Trustpilot sur un envoi vers serveur personnel retiré sans prévenir, fatigue des frais de mise à jour | coût et frais de mise à jour |
| Shottr | OCR, rapidité, légèreté, annotation (8 commentaires et plus) | ni vidéo ni GIF ; outils d'annotation plus simples que CleanShot | besoin de vidéo, donc CleanShot |
| Loom | lien instantané, commentaires, analyses, montage par transcription | offre gratuite pauvre (5 min), pratiques commerciales jugées agressives, capture d'onglet Chrome peu fiable | prix, limites gratuites, envie d'auto-hébergement |
| Cap | lien instantané, bons effets de zoom pour le prix, open source, support rapide | plantages et échecs de lancement, enregistrement multi-écrans qui ne démarre pas, exports lents en mode Studio, éditeur de captures à polir ; « version bêta » selon le fondateur | la fiabilité (un utilisateur est revenu à Screen Studio) |
| Kap | aucun retour direct trouvé | maintenance non vérifiée | n/a |
| Recordly | gratuit, zoom auto, curseur lissé, flou de mouvement, fonds, GIF | pas d'affichage des touches, peu de contrôle audio | n/a |
| QuickTime / Cmd+Maj+5 | gratuit, référence de base | pas de lien, pas d'effets, trim basique, **fichiers énormes** (environ 105 MB pour un plein écran, 10 fois plus que OBS), pas de son du système | n/a |
| OBS | gratuit, puissant | courbe d'apprentissage, pensé pour le direct, pas de zoom auto ni d'éditeur | on passe à plus simple |

## Les qualités citées comme « obligatoires », par nombre de sources

1. Prix honnête, sans abonnement (achat unique avec option de mise à jour payante) : environ 6.
2. Fiabilité, pas de plantage, y compris après une mise à jour de macOS : environ 5.
3. Zoom auto soigné et curseur lissé : environ 5.
4. Local d'abord, vie privée, pas de cloud imposé : environ 4.
5. Édition de base (trim, vitesse, annotations dans la vidéo) : environ 4.
6. **Exports petits avec une taille cible** : environ 3. Un utilisateur de Screen Studio a demandé une
   taille maximale d'export (par exemple 15 Mo pour Twitter) ; la demande a eu 2 votes et a été
   **rejetée**.
7. Partage instantané et glisser le fichier ailleurs : environ 3.
8. Son du système et micro : environ 2.
9. Affichage des touches, contrôle audio fin : 1 (anecdote).
10. Natif et léger (pas Electron) : 1 à 2.

## Prix : ce qui est accepté ou détesté

Accepté : achat unique avec un an de mises à jour et renouvellement facultatif ; petits prix uniques
(Shottr environ 12 $, ScreenSnap Pro 29 $ ou 39 $, Debut 25 $, Screenium 59,99 $).
Détesté : abonnement mensuel pour une app de bureau (surtout 29 $/mois) ; mises à jour forcées ;
licence modifiée qui retire des fonctions aux acheteurs existants (CleanShot, Screen Studio) ;
outils gratuits qui ajoutent des rappels (Shottr, d'après un concurrent, non vérifié).

## Les trous

- Une app **native** avec zoom auto soigné et **une taille d'export maximale** : Screen Studio a refusé.
- « Enregistrer, rogner, annoter, exporter petit, glisser vers Twitter ou Slack » en un geste, sans
  compte cloud. CleanShot s'en approche mais casse après les mises à jour ; Shottr n'a pas de vidéo.
- **Annotations avec durée dans la vidéo** (un utilisateur de CleanShot les demande).
- Masquage qui suit un contenu qui bouge.
- Compatibilité honnête avec les mises à jour de macOS.

## Ce que l'étude suggère pour Méliès

1. Vendre en achat unique avec un an de mises à jour, jamais en abonnement seul.
2. Faire de la fiabilité l'argument n°1 : tester chaque bêta de macOS.
3. **Export vers une taille cible** (par exemple 15 Mo) avec un préréglage Twitter.
4. Local d'abord, sans compte.
5. Zoom auto avec contrôle manuel, curseur de zoom fin, désactivable.
6. Annotations avec durée (flèche, texte, spotlight, flou).
7. Trim et vitesse fiables dès le départ.
8. Glisser-déposer du fichier exporté et résultat rapide.
9. Micro et son du système simples, compte à rebours 3-2-1.
10. À éviter : Electron lourd, interface cachée, retirer des fonctions aux acheteurs, rappels
    d'achat insistants. Garder le GIF honnête (la qualité des GIF de CleanShot est critiquée).

## Sources principales

hn.algolia.com (fils sur Screen Studio, Loom, Cap, OpenScreen, Shottr), alternativeto.net (actualité
sur la fin de la licence de Screen Studio), hub.screen.studio (demande de taille maximale d'export),
setapp.com (avis CleanShot X, Xnapper), producthunt.com (avis Cap), trustpilot.com (CleanShot),
macmost.com (taille des fichiers QuickTime), thesweetbits.com (Recordly), macstories.net et
macworld.com (ScreenFloat). Les articles de blogs de concurrents (ScreenSnap Pro, Layerpath, Arcade)
sont à prendre avec prudence.
