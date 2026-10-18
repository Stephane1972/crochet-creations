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
| 1 | Projet Flutter, thème rose/vert, mode jour/nuit, navigation, logo, splash, accueil | terminée (PR #1, en attente de fusion) |
| 2 | Base de données, modèles, migrations, repositories | **à valider** |
| 3 | Produits et stock | à venir |
| 4 | Clients | à venir |
| 5 | Ventes et panier | à venir |
| 6 | Factures PDF | à venir |
| 7 | Devis | à venir |
| 8 | Cours et inscriptions | à venir |
| 9 | Dépenses | à venir |
| 10 | Statistiques | à venir |
| 11 | Sauvegarde / export | à venir |
| 12 | Tests, corrections, optimisation de l'interface | à venir |

### Ce que contient l'étape 2

- **Base de données SQLite** sur le téléphone (15 tables : produits, variantes, photos, clients, ventes, lignes de
  vente, paiements, factures, devis, lignes de devis, cours, inscriptions, dépenses, réglages, numérotation),
  entièrement hors ligne.
- **Garde-fous dans la base** : pas de stock ni de montant négatif, totaux toujours cohérents, numéros de facture
  et de devis uniques, une seule facture émise par vente…
- **Règles de calcul** testées : total d'une vente (remise, frais de port), statut de paiement, alertes de stock,
  numérotation `FACT-2026-0001` / `DEVIS-2026-0001` (une suite par année, sans trou).
- **Accès aux données** (repositories) pour les produits (variantes, photos, stock), les clients, les réglages
  et la numérotation.
- **Le mode jour / nuit choisi dans *Plus → Réglages* est maintenant mémorisé** entre deux lancements.
- Si la base ne peut pas s'ouvrir, un écran en français explique quoi faire au lieu d'un écran blanc.

Visible sur le téléphone : surtout la mémorisation du mode jour/nuit. L'écran d'accueil affiche encore « — » :
les écrans qui lisent et écrivent dans la base arrivent aux étapes 3 à 10.

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
