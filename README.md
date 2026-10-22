# Crochet & Créations

Application Android de gestion pour une créatrice auto-entrepreneuse qui vend des objets en crochet,
des doudous, des boucles d'oreilles, des accessoires faits main, des créations personnalisées et des
cours de crochet.

Elle permet de gérer le **catalogue et le stock**, les **clients**, les **ventes**, les **factures PDF**,
les **devis**, les **cours et inscriptions**, les **dépenses**, des **statistiques simples**
et les **sauvegardes**. Elle fonctionne **entièrement hors ligne**, sans serveur.

> Nom provisoire : « Crochet & Créations ».

## État d'avancement

Le développement se fait en 12 étapes validées une par une (détail dans [ROADMAP.md](ROADMAP.md)).

| Étape | Contenu | État |
|------:|---------|------|
| 1 | Projet Flutter, thème rose/vert, mode jour/nuit, navigation, logo, splash, accueil | terminée et validée |
| 2 | Base de données, modèles, migrations, repositories | terminée et validée |
| 3 | Produits et stock | terminée et validée |
| 4 | Clients | **à valider** (PR #4) |
| 5 | Ventes et panier | à venir |
| 6 | Factures PDF | à venir |
| 7 | Devis | à venir |
| 8 | Cours et inscriptions | à venir |
| 9 | Dépenses | à venir |
| 10 | Statistiques | à venir |
| 11 | Sauvegarde / export | à venir |
| 12 | Tests, corrections, optimisation de l'interface | à venir |

### Ce que contient l'étape 4 : clients

- **Onglet Clients** : liste triée par nom, avec **recherche** (sans tenir compte des accents ni des majuscules :
  nom, raison sociale, téléphone — même sans les espaces —, e-mail, adresse, ville, SIREN/SIRET, notes) et filtres
  **Particuliers**, **Professionnels** et **Archivés**. Un professionnel s'affiche sous le nom de son entreprise,
  avec la personne à contacter dessous.
- **Fiche client** : coordonnées (civilité, téléphone, e-mail, adresse, SIREN/SIRET pour un professionnel, notes) et
  **historique** : ventes (avec le total des ventes validées), paiements, factures, devis et cours. Chaque rubrique
  montre les 5 plus récents, avec « Voir tout » pour déplier. Actions : Modifier, **Archiver / Restaurer** (avec
  confirmation).
- **Ajout et modification** : choix Particulier ou Professionnel (la raison sociale et le SIREN/SIRET n'apparaissent
  que pour un professionnel), contrôle du nom, du téléphone, de l'e-mail, du code postal et du SIREN (9 chiffres) ou
  SIRET (14 chiffres). Un client n'a besoin que d'un prénom, d'un nom ou d'une raison sociale. Quitter un formulaire
  modifié demande confirmation.
- **Accueil** : la tuile « Nouveau client » ouvre le formulaire.

À savoir : l'historique d'un client reste vide tant que les ventes, factures, devis et cours n'existent pas
(étapes 5 à 8). Le « client de passage » (vente rapide sans fiche) sera proposé avec les ventes, à l'étape 5.

### Ce que contient l'étape 3 : produits et stock

- **Onglet Produits** : catalogue avec **recherche** (sans tenir compte des accents ni des majuscules : nom,
  référence, catégorie, matières, couleur, description, variantes) et **filtres** (catégorie, « à réapprovisionner »,
  archivés). Chaque produit montre sa photo, son prix, son stock et ses alertes **Épuisé** / **Stock faible**.
- **Fiche produit** : photos à faire défiler, informations, stock (avec ajustement rapide), **variantes** (couleur,
  taille, prix et stock propres), **historique des ventes**, et les actions Modifier, **Dupliquer**,
  **Archiver / Restaurer** (avec confirmation), Vendre et Ajouter au panier.
- **Ajout et modification** : formulaire vérifié champ par champ (nom, catégorie et prix obligatoires), photo
  principale et autres photos (appareil photo ou galerie), temps de fabrication, coût des matières, stock, seuil
  d'alerte, statut, « personnalisable ». La référence `PRD-0001`… est attribuée automatiquement.
  Quitter un formulaire modifié demande confirmation.
- **Accueil** : la tuile « Stock faible » compte les produits à réapprovisionner et ouvre la liste filtrée.

À savoir : « Vendre » et « Ajouter au panier » ouvrent pour l'instant l'onglet Vente, encore provisoire
(le panier arrive à l'étape 5). L'historique des ventes se remplira à partir de cette étape.

(Les étapes 1 et 2 — fondations et base de données — sont décrites dans [CHANGELOG.md](CHANGELOG.md).)

## Essayer l'application

### Option A — Télécharger l'APK construit par GitHub (aucune installation)

1. Sur le téléphone, ouvrir le dépôt sur GitHub (navigateur ou application) → section **Releases**
   (https://github.com/Stephane1972/crochet-creations/releases).
2. Ouvrir la pré-version **« APK de test — … »** de la branche voulue et télécharger le fichier
   `crochet-creations-XXXXXXX.apk` (XXXXXXX = numéro du commit).
3. Ouvrir le fichier téléchargé. Android demandera d'autoriser l'installation d'applications de
   sources inconnues pour l'application utilisée (Chrome, Fichiers…).

Une construction se lance automatiquement à chaque envoi sur `main` et sur chaque pull request ;
on peut aussi la lancer à la main (**Actions → Android → Run workflow**). La pré-version d'une branche
est remplacée à chaque nouvel envoi. L'APK est aussi proposé en « artefact » dans l'onglet Actions
lorsque le quota de stockage du compte GitHub le permet.

### Option B — Lancer en local (nécessite Flutter)

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) (canal *stable*) et Android Studio
(ou un téléphone en mode développeur).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # génère le code de la base de données
bash tool/setup_android.sh   # crée le dossier android/, le nom de l'app et les icônes (une seule fois)
flutter run                  # sur un téléphone branché ou un émulateur
flutter test                 # lance les tests
flutter analyze              # vérifie la qualité du code
```

Flutter doit être récent (canal *stable*, Flutter 3.38 / Dart 3.10 au minimum). Les fichiers `*.g.dart` générés par
`build_runner` ne sont pas versionnés : relancer la commande de génération après chaque `git pull` qui modifie
`lib/data/database/tables.dart`.

> Le dossier `android/` n'est volontairement **pas** versionné : il est généré par `tool/setup_android.sh`
> (voir [ARCHITECTURE.md](ARCHITECTURE.md), section « Dossier android/ »).

## Structure du dépôt

```
lib/            code de l'application : presentation, domain, data (voir ARCHITECTURE.md)
assets/         logo SVG, icônes, police Poppins
test/           tests automatiques
tool/           scripts : génération des icônes et du dossier android/, annotations de la CI
.github/        construction automatique de l'APK
```

L'organisation détaillée du code est expliquée dans [ARCHITECTURE.md](ARCHITECTURE.md).

## Règles françaises prises en compte

L'utilisatrice est micro-entrepreneuse et bénéficie de la **franchise en base de TVA** :

- aucun calcul de TVA, les prix affichés sont des prix finaux ;
- chaque facture portera la mention « TVA non applicable, article 293 B du CGI » ;
- factures et devis auront une numérotation unique et chronologique (`FACT-2026-0001`, `DEVIS-2026-0001`…) ;
- le chiffre d'affaires *ventes d'objets* et celui des *cours/prestations* seront suivis séparément,
  avec une alerte à l'approche des seuils de **85 000 €** (biens) et **37 500 €** (services).

Ces règles seront mises en œuvre aux étapes 5, 6, 7 et 10. L'application n'est pas un conseil comptable :
en cas de doute, se rapprocher d'un expert-comptable ou de l'URSSAF.

## Méthode de travail

- Une **branche par étape**, des commits courts et clairs, une **pull request par fonctionnalité terminée**.
- Chaque pull request explique ce qui a été ajouté, les fichiers modifiés, comment tester et ce qui reste à faire.
- Rien n'est fusionné dans `main` sans validation.
- Voir [CHANGELOG.md](CHANGELOG.md) pour l'historique des versions.
