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
| 1 | Projet Flutter, thème rose/vert, mode jour/nuit, navigation, logo, splash, accueil | **à valider** |
| 2 | Base de données, modèles, migrations, repositories | à venir |
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

### Ce que contient l'étape 1

- Thème Material 3 rose pastel / vert sauge, **mode jour, nuit ou automatique** (choix dans *Plus → Réglages*).
- Logo (pelote de laine rose + crochet vert) en SVG, version monochrome pour les factures, icône Android.
- Écran de démarrage (splash) avec le logo.
- Navigation à 5 onglets : Accueil · Produits · Vente · Clients · Plus.
- Écran d'accueil (tableau de bord) : raccourcis, emplacements des chiffres clés, suivi des seuils de franchise de TVA.
- Les écrans des étapes suivantes affichent « Bientôt disponible », avec l'étape où ils seront construits.

Pour l'instant **aucun chiffre n'est calculé** (pas encore de base de données) : l'accueil affiche « — ».

## Essayer l'application

### Option A — Télécharger l'APK construit par GitHub (aucune installation)

1. Sur GitHub, ouvrir le dépôt → onglet **Actions** → workflow **Android (analyse, tests, APK)**.
2. Ouvrir la dernière exécution (pastille verte ou rouge) → section **Artifacts** en bas de page.
3. Télécharger **crochet-creations-apk** (un fichier .zip contenant `app-release.apk`).
4. Copier `app-release.apk` sur le téléphone Android et l'ouvrir. Android demandera d'autoriser
   l'installation d'applications de sources inconnues pour l'application utilisée (Fichiers, Chrome…).

Une exécution se lance automatiquement à chaque envoi sur `main` et à chaque pull request.
On peut aussi la lancer à la main : **Actions → Android → Run workflow**.

### Option B — Lancer en local (nécessite Flutter)

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) (canal *stable*) et Android Studio
(ou un téléphone en mode développeur).

```bash
flutter pub get
bash tool/setup_android.sh   # crée le dossier android/, le nom de l'app et les icônes (une seule fois)
flutter run                  # sur un téléphone branché ou un émulateur
flutter test                 # lance les tests
flutter analyze              # vérifie la qualité du code
```

> Le dossier `android/` n'est volontairement **pas** versionné : il est généré par `tool/setup_android.sh`
> (voir [ARCHITECTURE.md](ARCHITECTURE.md), section « Dossier android/ »).

## Structure du dépôt

```
lib/            code de l'application (voir ARCHITECTURE.md)
assets/         logo SVG, icônes, police Poppins
test/           tests automatiques
tool/           scripts : génération des icônes et du dossier android/
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
