# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.3.0] — Étape 3 : produits et stock (en attente de validation)

### Ajouté
- Onglet **Produits** (écran 3) : liste avec recherche sans accents ni majuscules (nom, référence, catégorie, matières,
  couleur, description, variantes), filtres par catégorie, « à réapprovisionner » et archivés, étiquettes
  Épuisé / Stock faible / Sur commande / Masqué / Archivé, état vide.
- **Fiche produit** (écran 4) : photos, informations, stock avec ajustement (inventaire), variantes (ajout, modification,
  archivage et restauration), historique des ventes, modifier, dupliquer, archiver / restaurer avec confirmation,
  boutons Vendre et Ajouter au panier.
- **Formulaire produit** (écran 5) : validation champ par champ, photo principale et photos secondaires
  (appareil photo ou galerie), temps de fabrication en heures et minutes, montants saisis en euros (virgule ou point),
  confirmation avant d'abandonner une saisie.
- Photos copiées dans le dossier privé de l'application (réduites à 1 600 px) ; la base ne garde que le nom du fichier.
  Les fichiers devenus inutiles sont supprimés (jamais avant l'enregistrement pour une photo déjà enregistrée).
- Accueil : la tuile « Stock faible » compte les produits à réapprovisionner et ouvre la liste filtrée.
- Accès aux données : résumés du catalogue et fiche mis à jour automatiquement, duplication, inventaire,
  historique des ventes, photos enregistrées avec le produit.
- Règles testées : alerte de stock d'un produit à variantes, produit vendable ou non, noms de variantes uniques.

### Modifié
- Un nom de variante déjà pris est refusé avec un message clair (au lieu d'une erreur technique de la base).
- `ProduitRepository.creer` et `modifier` acceptent des photos (paramètres facultatifs : appels existants inchangés).
- Le texte des réglages indique « étape 3 sur 12 ».

### Limites connues
- « Vendre » et « Ajouter au panier » ouvrent l'onglet Vente, encore provisoire, jusqu'à l'étape 5.
- L'historique des ventes reste vide tant qu'aucune vente ne peut être enregistrée (étape 5).
- Dupliquer ne copie pas les photos et remet le stock à zéro (la copie est ouverte pour être complétée).
- Si Android ferme l'application pendant la prise d'une photo, celle-ci n'est pas récupérée (à traiter à l'étape 12).
- Le schéma de la base n'a pas changé : pas de migration.

## [0.2.0] — Étape 2 : base de données

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
