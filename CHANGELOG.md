# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.2.0] — Étape 2 : base de données (en attente de validation)

### Ajouté
- Base de données SQLite hors ligne avec Drift : 15 tables (produits, variantes, photos secondaires, clients, ventes,
  lignes de vente, paiements, factures, devis, lignes de devis, cours, inscriptions, dépenses, réglages, numérotation).
- Clés étrangères activées, index sur les champs recherchés, contraintes de cohérence (noms non vides, montants et
  stocks positifs, totaux exacts, numéros uniques, une seule facture émise par vente…), suppression douce.
- Migration versionnée (version 1), avec vérification des liaisons après une mise à jour.
- Règles de calcul testées : total d'une vente (remise en % ou en montant, frais de port, arrondi au centime),
  statut de paiement (payée, partielle, impayée, remboursée), alertes de stock, format des numéros.
- Numérotation continue `FACT-AAAA-NNNN`, `DEVIS-AAAA-NNNN` (une suite par année) et références produit `PRD-NNNN`,
  sans trou si l'enregistrement échoue.
- Accès aux données (repositories) : produits (variantes, photos, stock « tout ou rien »), clients, réglages, numérotation.
- Le mode jour / nuit / automatique est mémorisé entre deux lancements.
- Écran d'erreur en français si la base ne peut pas s'ouvrir.
- Tests sur une base SQLite en mémoire (structure, contraintes, numérotation, stock, archivage).
- CI : génération du code Drift, annotations lisibles des échecs de chaque étape, APK publié même si un test échoue.

### Modifié
- Dart 3.10 / Flutter 3.38 minimum (exigé par Drift).
- Les fichiers `*.g.dart` générés ne sont pas versionnés.

### Limites connues
- Aucun écran ne lit encore la base (sauf le mode jour/nuit) : l'accueil affiche toujours « — ».
- Ventes, factures, devis, cours, dépenses : tables et contraintes prêtes, mais leurs repositories (avec la logique
  propre à chaque écran) arrivent avec leur étape.
- Hypothèses de schéma à confirmer : voir ARCHITECTURE.md, « Hypothèses du schéma ».
- La migration n'a jamais eu à convertir de vraies données (version 1 seulement).

## [0.1.0] — Étape 1 : fondations

### Ajouté
- Projet Flutter (Dart, Material 3, Riverpod) organisé en couches `presentation` / `domain` / `data`.
- Thèmes jour et nuit aux couleurs de la charte (rose pastel, rose soutenu, vert sauge), avec contrastes
  de texte vérifiés par des tests ; mode automatique, jour ou nuit au choix dans *Plus → Réglages*.
- Titres en Poppins (police embarquée), texte courant en police système ; boutons arrondis, cartes à ombre légère.
- Logo SVG (pelote de laine rose et crochet vert), version monochrome pour les factures,
  icône Android (classique, adaptative et monochrome).
- Écran de démarrage avec le logo.
- Navigation à 5 onglets (Accueil, Produits, Vente, Clients, Plus) ; le bouton « retour » ramène à l'accueil.
- Écran d'accueil : en-tête (salutation et date), raccourcis, emplacements des chiffres clés,
  suivi des seuils de franchise de TVA (85 000 € / 37 500 €).
- Écrans « Bientôt disponible » pour les écrans des étapes suivantes.
- Interface entièrement en français.
- Utilitaires `formatEuros` (montants en centimes) et dates en français.
- Documentation : README, ARCHITECTURE, ROADMAP, CHANGELOG.
- Tests unitaires (montants, dates, thèmes, contrastes) et tests de widgets (splash, navigation, thème).
- Construction automatique de l'APK avec GitHub Actions (analyse, tests, APK publié dans une pré-version), scripts `tool/setup_android.sh` et `tool/generate_icons.py`.

### Limites connues
- Aucun chiffre n'est calculé : pas encore de base de données (étape 2).
- Le choix jour/nuit n'est pas mémorisé entre deux lancements (corrigé à l'étape 2).
- Le code est analysé, testé et compilé en APK par GitHub Actions, mais n'a pas encore été essayé sur un téléphone.
