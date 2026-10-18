# Architecture

Ce document explique comment le code est organisé, pour pouvoir le faire évoluer étape après étape
sans que les écrans, la logique métier et la base de données se mélangent.

## Vue d'ensemble : trois couches

```
presentation  →  domain  →  data
  (écrans)      (règles)   (base SQLite, fichiers)
```

| Couche | Rôle | Dépend de |
|--------|------|-----------|
| `presentation` | Écrans, widgets, navigation, états Riverpod propres à l'interface | `domain`, `core` |
| `domain` | Règles métier pures en Dart : totaux d'une vente, décrémentation du stock, numérotation, conversion devis → facture, statistiques. Aucune dépendance à Flutter ni à la base | rien (sauf `core`) |
| `data` | Base SQLite, migrations, repositories, fichiers (photos, PDF, sauvegardes) | `domain` |

Règles :

- Un écran ne parle **jamais** directement à la base : il passe par un *provider* Riverpod qui appelle un repository.
- La logique métier vit dans `domain` et se teste sans interface ni base de données (tests unitaires rapides).
- `core` regroupe ce qui est partagé et sans logique métier : thème, constantes, utilitaires, widgets génériques.

## Arborescence (étape 1)

```
crochet-creations/
├── .github/workflows/android.yml     construction automatique : analyse, tests, APK
├── assets/
│   ├── fonts/                        Poppins (titres) + licence OFL
│   ├── icon/                         PNG d'icône générés (voir tool/generate_icons.py)
│   └── images/                       logo.svg (couleur) et logo_mono.svg (monochrome)
├── lib/
│   ├── main.dart                     point d'entrée (ProviderScope)
│   ├── app.dart                      MaterialApp : thèmes, langue française, routes
│   ├── core/
│   │   ├── constants/app_constants.dart      nom, version, seuils de franchise de TVA
│   │   ├── router/app_routes.dart            noms des routes
│   │   ├── theme/
│   │   │   ├── app_colors.dart               palette de la charte + teintes dérivées
│   │   │   ├── app_theme.dart                thèmes Material 3 jour et nuit
│   │   │   └── theme_mode_provider.dart      choix auto / jour / nuit (Riverpod)
│   │   ├── utils/
│   │   │   ├── money.dart                    formatEuros (montants en centimes)
│   │   │   └── date_fr.dart                  dates et salutation en français
│   │   └── widgets/
│   │       ├── app_logo.dart                 logo SVG
│   │       └── adaptive_system_overlay.dart  icônes de la barre d'état selon le thème
│   ├── domain/                       (vide pour l'instant : règles métier, dès l'étape 2)
│   ├── data/                         (vide pour l'instant : base de données, étape 2)
│   └── presentation/
│       ├── common/                   placeholder_screen.dart, menu_tile.dart
│       ├── home/home_screen.dart             accueil / tableau de bord
│       ├── more/more_screen.dart             onglet « Plus »
│       ├── router/app_router.dart            route → écran
│       ├── settings/settings_screen.dart     réglages (thème)
│       ├── shell/                            barre de navigation + onglet courant
│       └── splash/splash_screen.dart         écran de démarrage
├── test/                             tests unitaires et de widgets
├── tool/
│   ├── generate_icons.py             logo SVG → PNG d'icône
│   └── setup_android.sh              crée android/, règle le nom, génère les icônes
├── pubspec.yaml
└── analysis_options.yaml
```

Chaque fonctionnalité des étapes suivantes ajoutera ses dossiers dans les trois couches, par exemple pour
les produits : `domain/produits/`, `data/produits/`, `presentation/produits/`.

## Conventions

- **Langue** : noms métier en français (`facture`, `client`, `stock`), vocabulaire technique en anglais
  (`Provider`, `Repository`). Commentaires en français lorsqu'ils sont utiles.
- **Montants en centimes (entiers)** : `1250` pour 12,50 €. Aucun nombre à virgule pour l'argent, afin
  d'éviter les erreurs d'arrondi sur les factures. L'affichage passe par `formatEuros`.
- **Dates** : stockées en UTC (ISO 8601) dans la base, affichées en heure locale.
- **Suppression** : « soft delete » (colonne `archive_le`) pour tout ce qui a un historique
  (produits, clients, cours…). Les factures émises ne se suppriment jamais.

## Gestion d'état : Riverpod

`ProviderScope` entoure l'application (`main.dart`). Pour l'instant, deux états :

- `themeModeProvider` : mode d'affichage choisi (auto / jour / nuit) ;
- `navIndexProvider` : onglet affiché, ce qui permet à l'accueil de basculer vers l'onglet Vente.

Le choix du thème n'est pas encore mémorisé entre deux lancements : il le sera à l'étape 2,
avec la table `parametres_entreprise`.

## Navigation

Navigation Flutter standard (`Navigator` + routes nommées), sans bibliothèque supplémentaire :

- `AppRoutes` liste les noms de routes ; `AppRouter.onGenerateRoute` les associe aux écrans ;
- `MainShell` porte la barre à 5 onglets (Accueil · Produits · Vente · Clients · Plus) avec `IndexedStack`,
  ce qui conserve l'état de chaque onglet (par exemple une vente en cours) quand on change d'onglet ;
- les autres écrans (factures, devis, cours…) s'ouvrent par-dessus, depuis *Plus* ou l'accueil ;
- le bouton « retour » d'Android ramène d'abord à l'accueil avant de quitter l'application ;
- tant qu'un écran n'est pas développé, sa route affiche `PlaceholderScreen` (« Bientôt disponible »).
  Quand une étape livre un écran, on le retire de `EcransAVenir.parRoute` et on ajoute un `case` dans `AppRouter`.

## Thème et identité visuelle

- Les couleurs de la charte sont dans `app_colors.dart` ; `app_theme.dart` construit deux
  `ColorScheme` Material 3 complets (jour et nuit). Le mode automatique est géré par `MaterialApp.themeMode`.
- Titres en **Poppins** (fichiers embarqués, donc disponibles hors ligne) ; texte courant en police système (Roboto).
- Boutons en pilule, cartes arrondies avec ombre légère (liseré fin en mode nuit), champs de saisie arrondis.
- **Contraste** : le blanc sur le vert sauge foncé `#6E9B7F` n'atteint que 3,1:1 (la norme demande 4,5:1).
  Les boutons principaux utilisent donc un texte vert très sombre (`encreSurSauge`, 4,9:1), et les liens sur
  fond clair un vert plus profond (`saugeTexte`, 5,1:1). Un test (`app_theme_test.dart`) vérifie tous les
  couples texte/fond dans les deux modes.
- **Logo** : `assets/images/logo.svg` (couleur) et `logo_mono.svg` (une couleur, pour les factures). Le même
  fichier s'affiche dans l'application (`flutter_svg`) et pourra être intégré aux PDF (`pw.SvgImage`).
  Le logo ne contient pas de texte : le nom est composé en Flutter / dans le PDF avec la police du projet.

## Dossier `android/`

Le dossier `android/` n'est pas versionné. `tool/setup_android.sh` le crée avec `flutter create`,
règle le nom affiché (« Crochet & Créations ») et génère les icônes. La CI exécute ce script à chaque fois.

Conséquence à garder en tête pour les étapes suivantes : toute modification de configuration Android
(permissions caméra/photos pour `image_picker`, par exemple) devra être ajoutée à ce script.
Si cette contrainte gêne, on pourra versionner `android/` à la place (il suffit de retirer `/android/` du `.gitignore`).

## Choix techniques à confirmer

| Sujet | Décision proposée | À confirmer à |
|-------|-------------------|---------------|
| Base de données | **Drift** (SQLite) : requêtes vérifiées à la compilation, migrations versionnées, flux de données réactifs, base en mémoire pour les tests. C'est le meilleur choix de maintenabilité parmi les deux options du cahier des charges | étape 2 |
| Dépendances ajoutées à l'étape 1 | `flutter_riverpod` (imposée), `flutter_svg` (affichage du logo SVG), `flutter_localizations` (SDK, interface en français). Rien d'autre : `pdf`, `printing`, `share_plus`, `image_picker`, `path_provider`… arriveront avec les étapes qui s'en servent | étape 1 |
| Mémorisation du mode jour/nuit | Dans la base (étape 2), pas de bibliothèque supplémentaire | étape 2 |

## Tests

- `test/core/` : montants, dates, thèmes (couleurs de la charte et contrastes), mode d'affichage.
- `test/widget_test.dart` : le splash mène à l'accueil, les 5 onglets, les raccourcis, le changement jour/nuit.

À partir de l'étape 2, les règles métier (total d'une vente, stock, numérotation, conversion devis → facture,
statistiques) seront testées dans `test/domain/`, sans interface.

Commandes : `flutter analyze` puis `flutter test`.
