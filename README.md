# Textile Time Study — analyse du travail sur vidéo (confection)

Application Flutter (Android d'abord, puis Windows) de **chronométrage / analyse du travail sur vidéo**
pour les ateliers de confection. Interface en français. 100 % outils gratuits / open source.

Principe : on filme l'opération, **l'IA (Google Gemini, clé gratuite) propose le découpage** de la vidéo en
éléments de travail, puis le technicien méthodes **corrige** ce découpage sur la vidéo. L'appli calcule les temps
normaux et standards, le **SMV/SAM**, le **% de valeur ajoutée** et la production horaire, et exporte une
**fiche opération PDF** (structure opération → éléments + temps) et un **CSV**.

> Les codes et tables de temps GSD (GSD / Coats) sont propriétaires : ils ne sont **pas** utilisés.
> L'appli fournit une **bibliothèque maison** de mouvements de confection, éditable.

## Téléchargement

Chaque push sur `main` construit l'APK Android et un ZIP Windows (GitHub Actions) publiés dans la release
**« latest »** : <https://github.com/belloumi79/textile-time-study/releases/tag/latest>

## Fonctions (v0.1)

1. **Études** : article, opération, machine / type de point, opératrice, date, allure (jugement, défaut 100 %),
   majoration (repos / besoins, défaut 15 %), rendement (pour la production réaliste). Liste des études.
2. **Vidéo** : filmer (Android) ou importer (Android / Windows) ; lecture ralentie ¼×, ½×, 1× ;
   image par image (~1/30 s) et sauts de ±0,5 s ; chrono affiché sur la vidéo.
3. **Découpage automatique IA** (Gemini) : la vidéo et la bibliothèque de mouvements sont envoyées ; l'IA renvoie
   un JSON strict (cycles, éléments avec début/fin, code, libellé, classe, valeur ajoutée, confiance).
   Le JSON est validé et normalisé (temps croissants, pas de chevauchement, codes inconnus → « Autre »).
   Vidéo ≤ 15 Mo : envoi direct ; au-delà : envoi « resumable » via la Files API.
   Erreurs (clé, quota, réseau) : message en français, la saisie manuelle reste possible.
4. **Éditeur de correction** : tableau synchronisé avec la lecture (ligne en surbrillance), toucher une ligne = aller
   à son début ; **Couper ici**, **Fusionner avec le suivant**, **Début ici / Fin ici**, **Nouveau cycle ici**,
   **Supprimer**, **Annuler** ; modification d'un élément (mouvement de la bibliothèque, nom, début/fin, allure,
   temps édité, valeur ajoutée). Saisie manuelle : choisir le mouvement puis **Début** / **Fin** pendant la lecture.
5. **Calculs** : temps normal = observé × allure / 100 ; plusieurs cycles → moyenne par élément ;
   temps standard = normal × (1 + majoration) ; SMV (min, 4 décimales) ; % VA ; pièces/heure à 100 % et au rendement.
6. **Histogramme coloré** des temps par élément (fl_chart) + résumé.
7. **Stockage local** en fichiers JSON (dossier Documents/TextileTimeStudy) : études, bibliothèque, vidéos, exports.
8. **Export** : fiche opération **PDF** (police DejaVu embarquée pour les accents) et **CSV** (séparateur `;`, virgule
   décimale, compatible Excel FR).

## Bibliothèque de mouvements (codes maison)

| Code | Mouvement | Classe | VA |
|---|---|---|---|
| P1 | Prendre pièce (1 main) | Prise | non |
| P2 | Prendre pièces (2 mains / plusieurs) | Prise | non |
| AL | Aligner / assembler les plis | Positionnement | non |
| PP | Positionner sous le pied | Positionnement | non |
| CD | Coudre droit | Couture | oui |
| CC | Coudre courbe | Couture | oui |
| CA | Coudre avec arrêt | Couture | oui |
| CF | Couper fil | Coupe | non |
| RT | Retourner / tourner la pièce | Positionnement | non |
| LS | Lisser / ajuster | Positionnement | non |
| MP | Lever / baisser le pied-de-biche | Positionnement | non |
| MA | Aiguille haut / bas | Positionnement | non |
| DP | Déposer / empiler | Dépose | non |
| CT | Contrôler | Contrôle | non |
| AT | Attente | Attente | non |
| DE | Déplacement | Attente | non |
| AU | Autre | Autre | non |

Tout est modifiable dans l'écran **Bibliothèque** (code, libellé, description pour l'IA, classe, VA, couleur).

## Clé IA gratuite

1. Aller sur <https://aistudio.google.com> → **Get API key** → créer une clé (gratuite).
2. Dans l'appli : **Réglages** → coller la clé (stockée chiffrée sur l'appareil), choisir le modèle
   (défaut `gemini-3.6-flash`) et le nombre d'images analysées par seconde (défaut 2).

⚠️ Sur l'offre gratuite, Google peut utiliser les contenus envoyés pour améliorer ses produits : informer
l'entreprise et l'opératrice avant d'envoyer une vidéo.

## Limites connues (v0.1)

- **Précision du découpage IA** : Gemini échantillonne la vidéo (2 images/s par défaut) ; les bornes proposées
  sont approximatives (±0,5 s) et les micro-gestes (< 1 s) peuvent être fusionnés ou mal classés. Le découpage
  IA est une **proposition à corriger**, pas une mesure.
- **Taille / quota** : pas de compression vidéo intégrée (filmer en 720p, 1 à 3 min, 2 à 5 cycles).
  Le quota gratuit Gemini (requêtes/minute, jetons/jour) peut être atteint : réessayer plus tard.
- Pas d'image par image exact : le pas de 1/30 s dépend des images clés de la vidéo.
- Moyenne multi-cycles **par position** : les cycles doivent avoir la même structure (un avertissement s'affiche sinon).
- Windows : pas de prise de vue (import uniquement) ; le CSV est enregistré dans le dossier exports (pas de partage).

## Développement

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # Android
flutter run -d windows # Windows
```

Structure : `lib/models` (Motion, StudyElement, Study), `lib/services` (calculs, éditeur de découpage,
IA Gemini + normalisation, stockage JSON, export PDF/CSV, réglages), `lib/screens`, `lib/widgets`, `test/`.
