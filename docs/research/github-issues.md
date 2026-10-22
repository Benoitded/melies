# Concurrents : ce que disent les tickets GitHub (2026-10-22)

Rapport d'un sous-agent de recherche, relu et condensé. Données : tous les tickets des dépôts publics
(`gh issue list`, PR exclues), classés par commentaires et réactions.

## Limites à connaître

- **Les comptes par thème sont des correspondances sur les titres seulement**, depuis avril 2025 (Kap :
  depuis 2021, car il n'a que 28 tickets récents). Ils se recouvrent, certains mots sont larges : ce sont
  des ordres de grandeur, pas des chiffres exacts. Environ 35 tickets lus en détail sur environ 3 000.
- Peu de réactions partout, sauf Kap (vieux tickets à 40 à 80 pouces levés). Les traqueurs de bugs
  surreprésentent les pannes et sous-représentent les satisfactions silencieuses.
- Le traqueur de Cap contient beaucoup de tickets générés par des robots (audits de sécurité), ce qui
  gonfle le thème « cloud ».

## Les dépôts

| Projet | Étoiles | Activité | Tickets | Remarque |
|---|---|---|---|---|
| Cap (Rust, Tauri) | 23,5 k | quotidienne | 806 (178 ouverts) | enregistreur open source, alternative à Loom |
| Kap (Electron) | 19,4 k | dernier envoi 2024-11 | 840 (230 ouverts) | pas de version depuis 2022 selon un ticket, la communauté se demande s'il est abandonné |
| Recordly (Electron) | 34,8 k | 2026-10-17 | 505 (268 ouverts) | copie libre de Screen Studio, tous les tickets depuis mars 2026 |
| OpenScreen | 39,9 k | archivé | 368 | continué dans `getopenscreen/openscreen` (4,8 k, actif, 355) |
| Screenize (Swift natif) | 0,6 k | en pause (mai 2026) | 30 | petit mais très pertinent |
| BetterCapture, better-shot, Azayaka (Swift) | 0,8 à 2,4 k | variable | 34 à 105 | signaux « app macOS native » |

## Thèmes qui reviennent, par ordre d'importance entre dépôts

1. **Fiabilité de l'export** : blocages, fichiers tronqués ou corrompus, export différent de l'aperçu,
   échecs sur gros fichiers. Plus grande catégorie de bugs partout (centaines de titres).
   Ex. Recordly : une vidéo d'une minute qui sort à 41 s, impossible d'exporter plus de 2 Go, blocage à 99 %.
   OpenScreen : « video decode ended early », MP4 corrompus. Cap : export figé à 102 % sur 13 min.
   Screenize : l'export ne correspond pas à l'aperçu.
2. **Audio** : micro manquant ou silencieux, son du système, écho, mauvais périphérique, décalage,
   corruption à la pause et reprise, dérive sur les longues prises. Domine chez Recordly (environ 93
   titres) et reste le plus ancien ticket non résolu de Kap (son du système, ouvert depuis 2017).
3. **Plantages au lancement, au démarrage ou à l'arrêt, et enregistrements qui ne produisent rien.**
4. **Autorisations, signature et confiance macOS** : boucles de demande d'autorisation, « endommagé » ou
   « logiciel malveillant » de Gatekeeper, applications non signées. Screenize : l'app supprimée
   automatiquement par macOS après la révocation d'une clé de signature. Reviennent presque partout.
5. **Performance et mémoire** : mémoire qui grossit sur les longs enregistrements (Cap : jusqu'à 15 Go),
   limite de 10 minutes (OpenScreen : tout l'enregistrement tenait en mémoire), CPU, export lent.
6. **Zoom auto, lissage du curseur, effets de clic** : le vœu n°1 (« pourquoi pas comme Screen Studio »).
   Les plaintes portent sur des bugs, pas sur l'idée : double curseur, curseur lissé en retard sur les
   clics, décalage en capture de fenêtre, dérive sur les longues prises.
7. **Choix de la cible de capture, multi-écrans** : de 80 à 100 tickets chez Cap et Recordly.
8. **Bases de l'éditeur** : annuler, couper, scinder, raccourcis, fusionner des clips, vitesse au-delà
   de 2×.
9. **Annotations, flou, clavier** : « le flou est une fonction de base » (OpenScreen), affichage des
   touches « essentiel pour les tutoriels » (Cap).
10. **Contrôle de la sortie** : dossier d'enregistrement, qualité et débit, **taille estimée du fichier**,
    compression, GIF, format pour Twitter (Kap).
11. Webcam en incrustation, distribution (Homebrew demandé dans 4 dépôts), santé des projets.

## Ce que les utilisateurs apprécient (peu de données)

Rendu soigné et résultat « à la Screen Studio » ; gratuit, sans filigrane ni abonnement ; mainteneur
qui répond vite ; pour Kap, la simplicité (barre de menu, zone, export).

## Pour Méliès : ce que ça implique

1. **Export ennuyeux et infaillible** : durée exportée égale à la source, aperçu identique à l'export,
   progression avec annulation.
2. **Écrire sur le disque pendant la capture** et pouvoir récupérer le dernier enregistrement après un
   plantage ; ne jamais écraser ni déplacer le fichier source (Screenize en a consommé un).
3. **L'audio comme citoyen de première classe** : pistes séparées, bon micro, changement de périphérique,
   pas de dérive sur 10 minutes et plus, pause et reprise corrects. À tester sur de longs clips.
4. **Export à taille cible avec estimation avant l'encodage** ; débit choisi selon le contenu (un débit
   trop bas rend le texte flou : OpenScreen).
5. **Zoom auto à partir des clics et du curseur, modifiable**. Éviter les pièges : double curseur, curseur
   lissé en retard, décalage en capture de fenêtre, dérive. Enregistrer la télémétrie du curseur à la
   capture (déjà fait).
6. **Choix de cible soigné** : zone, fenêtre, écran, mémorisation, déconnexion d'un écran, écran noir.
7. **Confiance macOS d'emblée** : signature développeur et notarisation, identifiant stable, assistant
   d'autorisation, détection « autorisé mais sans effet » avec relance, mise à jour automatique, Homebrew.
8. **Bases de l'éditeur avant les extras** ; puis annotations, flou, affichage des touches. Si on capte
   les touches, **ne jamais stocker le texte brut** (Screenize : les mots de passe étaient stockés en clair).
9. **Démarrage rapide et léger** (Kap : 3 à 10 s pour afficher la sélection, 45 à 61 réactions). Une app
   native évite la classe de bugs d'Electron.
10. **Éviter** : cloud, comptes, transcription, place de marché ; sorties de versions non testées et
    régressions à chaque version ; oublier une version de macOS (Sonoma, Sequoia, Tahoe, 27 bêta).
