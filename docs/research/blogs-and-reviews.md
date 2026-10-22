# Concurrents : blogs, pages éditeur, comparatifs (2026-10-22)

Rapport d'un sous-agent de recherche, relu et condensé. Sources : pages officielles (fonctions, prix,
changelogs), comparatifs (The Sweet Bits, Setapp), pages GitHub. Limites annoncées : aucun article
MacStories, 9to5Mac, Zapier ou TechRadar exploitable ; pas de fils Product Hunt ni Hacker News
(sauf les avis de Cap) ; le changelog de Screen Studio était vide ; plusieurs pages GitHub sans dates
de version. Une case « ? » veut dire non vérifié, pas « non ».

## Le fait marquant

**CleanShot X 5.0 (1er septembre 2026)** ajoute un mode Studio et un éditeur vidéo : zooms
intelligents, lissage du curseur, flou de mouvement, fonds personnalisés, taille du curseur après
coup, touches et caméra, export encodé par le matériel. L'outil de capture de référence entre donc
dans l'espace de Méliès. Prix : 35 $ une fois (un an de mises à jour). À tester en vrai : on ne sait
pas la qualité de ses zooms intelligents.

## Matrice (extrait, produits proches de Méliès)

| Fonction | CleanShot X | Screen Studio | Cap | Recordly | OpenScreen | Screenize |
|---|---|---|---|---|---|---|
| Micro | oui | oui | oui | oui | oui | oui |
| Son du système | oui | oui | ? | oui | oui | oui |
| Webcam | oui | oui | oui | oui | oui | ? |
| Curseur (clic, lissage, taille) | oui | le plus complet | ? | oui | oui | oui (ondulation) |
| Zoom auto | oui (Smart Zooms) | oui | ? | oui (suggestions) | oui | oui (2 modes) |
| Zoom manuel par points | ? | oui (2 styles) | oui | oui | oui | oui |
| Fond, marges, coins arrondis | oui | oui | oui | oui | oui | oui |
| Export GIF | oui | oui (jusqu'à 1080p) | ? | oui | oui | oui |
| Presets d'export MP4 | oui | oui | 4K / 60 i/s | oui | oui | oui |
| Rognage de l'image | ? | ? | ? | oui | oui | ? |
| Touches du clavier | oui | ? | ? | ? | non | oui |
| Compte à rebours, pause | oui | ? | pause, reprise | ? | ? | ? |
| Lien cloud | oui | oui (30 min) | oui | non | non | non |
| Glisser le fichier hors de l'éditeur | oui (aperçu rapide) | ? | ? | ? | ? | ? |
| Prix | 35 $ une fois | 9 $/mois (annuel) ou 29 $/mois | gratuit, 58 $ une fois | gratuit (AGPL) | gratuit (MIT, archivé) | gratuit (Apache, en pause) |

Autres : Shottr ne fait que les captures d'écran (défilante, OCR, règle, pas d'enregistrement),
pay-what-you-want autour de 12 $. ScreenFloat (17,99 $ une fois) a les marqueurs de coupe posés
pendant l'enregistrement. Loom, Tella, Zight, Descript sont du cloud par utilisateur et par mois.
QuickTime / Cmd+Maj+5 : gratuit, minuteur, clics, vignette qu'on peut glisser, pas de son système.

## Socle commun et différenciateurs

Socle (presque tous) : capture de zone, fenêtre ou plein écran, micro, trim, export MP4, export GIF,
fonds / marges / coins arrondis, clics visibles, zoom auto pour la classe « démo soignée ».

Différenciateurs (un ou deux produits) : défilante et OCR (CleanShot, Shottr, Snagit) ; masquage
automatique des données sensibles (Xnapper, captures seulement) ; marqueurs de coupe pendant
l'enregistrement (ScreenFloat) ; zoom planifié par activité (Screenize) ; suréchantillonnage et curseur
en boucle (Screen Studio) ; montage par transcription (Tella, Descript) ; auto-hébergement (Cap) ;
local seulement, sans compte (Shottr, Xnapper, Recordly, QuickTime).

**Pas trouvé chez les concurrents lus : combiner deux vidéos.** Non cherché précisément, donc à
vérifier avant de s'en vanter.

## Prix

Gratuit open source (Kap, Recordly, OpenScreen, Screenize, OBS, Cap gratuit) ; 12 $ (Shottr) ;
18 $ (ScreenFloat) ; 35 $ (CleanShot X) ; 58 $ (Cap bureau, usage commercial) ; abonnement
(Screen Studio 108 $/an, Snagit environ 40 €/an) ; par utilisateur et par mois (Loom, Tella, Zight,
Descript, 10 à 65 $). Screen Studio a supprimé la licence à vie : il ne reste que CleanShot (35 $)
et Cap (58 $) comme app « démo soignée » à prix unique. Les concurrents gratuits sont des apps
Electron multiplateformes : une app **native, signée, à prix unique ou gratuite**, se distingue par
la vitesse, la taille des fichiers, la fiabilité et la vie privée, pas par le nombre de fonctions.

## Feuille de route proposée par l'étude (priorité, effort)

| # | Fonction | Effort |
|---|---|---|
| 1 | Noyau d'enregistrement fiable : zone / fenêtre / plein écran, micro et son, compte à rebours, pause, raccourci global, reprise après plantage | moyen |
| 2 | Préréglage d'export « Twitter » avec budget de taille (H.264 / AAC, 1080p ou 720p, débit calculé pour rester sous la limite, estimation de taille en direct) ; limites à confirmer sur l'aide officielle de X | petit |
| 3 | Zoom auto à partir des clics et de la frappe, modifiable comme des points avec courbes | grand |
| 4 | Curseur : lissage, taille après coup, ondulation au clic, masquage au repos, flou de mouvement | moyen |
| 5 | Fonds, marges, coins arrondis, ombre, préréglages | petit |
| 6 | Glisser le fichier hors de l'éditeur + vignette rapide après l'enregistrement | petit |
| 7 | Annotations sur la timeline (flèche, texte, spotlight, flou avec durée) | moyen |
| 8 | Combiner deux vidéos | moyen |
| 9 | Rognage et vitesse par segment | petit |
| 10 | Export GIF avec plafond de taille | petit |
| 11 | Marqueurs de coupe posés pendant l'enregistrement | petit |
| 12 | Affichage des touches | moyen |
| 13 | OCR sur une image et masquage automatique (e-mails, clés d'API) | moyen |

À ne pas faire (pour l'instant) : hébergement cloud, liens de partage, analyses de visionnage,
espaces d'équipe ; transcription et suppression des mots parasites par IA ; suite de captures d'écran
(défilante, annotation d'images) ; Windows et Linux ; direct et scènes (OBS) ; place de marché de
plugins.

## Risques et inconnues

- CleanShot X 5.0 est la menace principale : à tester en vrai.
- Recordly et OpenScreen avancent vite et sont gratuits.
- Non vérifié : changelog de Screen Studio, dernière version de Kap, licence et version actuelle de
  Cap, limites actuelles de X (source tierce seulement).
- Les accusations sur les prix de Loom viennent de sites concurrents : non fiables.

## Sources principales

cleanshot.com (pricing, features, changelog), screen.studio, cap.so/pricing,
github.com/CapSoftware/Cap, github.com/webadderall/Recordly, github.com/siddharthvaddem/openscreen,
github.com/syi0808/screenize, github.com/wulkano/Kap, getkap.co, shottr.cc, xnapper.com,
eternalstorms.at/screenfloat, loom.com/pricing, techsmith.com (Snagit), zight.com, tella.com,
descript.com/pricing, obsproject.com, support.apple.com (capture et enregistrement),
thesweetbits.com (CleanShot vs Shottr, Recordly), setapp.com (CleanShot vs Shottr),
producthunt.com (avis de Cap), postfa.st (tailles vidéo X), newreleases.io (Cap v0.5.9).
