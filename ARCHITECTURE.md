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
| `domain` | Règles métier pures en Dart : listes de choix, totaux d'une vente, statut de paiement, règles de stock, format des numéros ; plus tard conversion devis → facture, statistiques. Aucune dépendance à Flutter ni à la base | rien |
| `data` | Base SQLite (Drift), migrations, repositories, fichiers (photos, PDF, sauvegardes) | `domain`, `core` |

Règles :

- Un écran ne parle **jamais** directement à la base : il passe par un *provider* Riverpod qui appelle un repository.
- La logique métier vit dans `domain` et se teste sans interface ni base de données (tests unitaires rapides).
- `core` regroupe ce qui est partagé et sans logique métier : thème, constantes, utilitaires, widgets génériques.
- **Modèles** : les classes de lignes générées par Drift (`Produit`, `Client`, `Vente`, `Facture`…) servent de
  modèles à toutes les couches. On n'a pas créé de seconde série de classes « métier » identiques : ce serait du
  code en double à maintenir. La couche `domain` contient les règles et les listes de choix, pas les entités.

## Arborescence (étape 2)

```
crochet-creations/
├── .github/workflows/android.yml     construction automatique : code généré, analyse, tests, APK
├── assets/
│   ├── fonts/                        Poppins (titres) + licence OFL
│   ├── icon/                         PNG d'icône générés (voir tool/generate_icons.py)
│   └── images/                       logo.svg (couleur) et logo_mono.svg (monochrome)
├── lib/
│   ├── main.dart                     ouvre la base, lit le mode jour/nuit, lance l'application
│   ├── app.dart                      MaterialApp : thèmes, langue française, routes
│   ├── core/
│   │   ├── constants/app_constants.dart      nom, version, seuils de TVA, mention « art. 293 B »
│   │   ├── router/app_routes.dart            noms des routes
│   │   ├── theme/
│   │   │   ├── app_colors.dart               palette de la charte + teintes dérivées
│   │   │   ├── app_theme.dart                thèmes Material 3 jour et nuit
│   │   │   └── theme_mode_provider.dart      choix auto / jour / nuit, mémorisé via la base
│   │   ├── utils/
│   │   │   ├── money.dart                    formatEuros (montants en centimes)
│   │   │   ├── date_fr.dart                  dates et salutation en français
│   │   │   └── texte.dart                    nettoyage des saisies facultatives
│   │   └── widgets/                          logo SVG, icônes de barre d'état
│   ├── domain/
│   │   ├── enums.dart                        listes de choix (catégories, statuts, modes de paiement…)
│   │   ├── erreurs.dart                      erreurs métier à message clair
│   │   └── calculs/
│   │       ├── totaux.dart                   sous-total, remise, frais de port, total
│   │       ├── statut_paiement.dart          payée / partielle / impayée / remboursée
│   │       ├── stock.dart                    alerte de stock, produit « sur commande »
│   │       └── numero_document.dart          FACT-2026-0001, DEVIS-2026-0001, PRD-0001
│   ├── data/
│   │   ├── database/
│   │   │   ├── tables.dart                   les 15 tables (contraintes, index)
│   │   │   ├── app_database.dart             base, version du schéma, migrations
│   │   │   └── app_database.g.dart           (généré par build_runner, non versionné)
│   │   ├── repositories/                     numérotation, réglages, produits, clients
│   │   └── providers.dart                    accès Riverpod à la base et aux repositories
│   └── presentation/
│       ├── common/                   placeholder_screen.dart, menu_tile.dart
│       ├── home/home_screen.dart             accueil / tableau de bord
│       ├── more/more_screen.dart             onglet « Plus »
│       ├── router/app_router.dart            route → écran
│       ├── settings/settings_screen.dart     réglages (thème)
│       ├── shell/                            barre de navigation + onglet courant
│       ├── splash/splash_screen.dart         écran de démarrage
│       └── startup/erreur_demarrage_app.dart écran d'erreur si la base ne s'ouvre pas
├── test/
│   ├── core/ domain/ data/ presentation/     tests (voir plus bas)
│   └── widget_test.dart                      parcours splash → accueil → réglages
├── tool/
│   ├── generate_icons.py             logo SVG → PNG d'icône
│   ├── setup_android.sh              crée android/, règle le nom, génère les icônes
│   └── ci_annoter.sh                 publie les erreurs de la CI en annotations lisibles
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
- **Dates** : Drift enregistre les dates en secondes depuis 1970 (UTC), donc sans ambiguïté de fuseau horaire ;
  elles sont relues et affichées en heure locale. L'année d'une facture est celle de sa date d'émission, en heure locale.
- **Suppression** : « soft delete » (colonne `archive_le`) pour produits, variantes, clients, cours et dépenses :
  l'élément est masqué mais l'historique reste intact. Les ventes, factures et devis ne s'archivent pas, ils
  changent de **statut** (une vente annulée remet le stock ; une facture émise ne se supprime jamais).

## Gestion d'état : Riverpod

`ProviderScope` entoure l'application (`main.dart`). États et accès actuels :

- `themeModeProvider` : mode d'affichage choisi (auto / jour / nuit). Il est **mémorisé** dans la table
  `parametres_entreprise` : `main()` le lit avant le premier écran (pas de clignotement) et chaque changement
  est enregistré en arrière-plan (`modeThemeInitialProvider`, `modeThemeStoreProvider`) ;
- `navIndexProvider` : onglet affiché, ce qui permet à l'accueil de basculer vers l'onglet Vente ;
- `appDatabaseProvider` et un provider par repository (`lib/data/providers.dart`). `appDatabaseProvider` est fourni
  par `main()` ; les tests le remplacent par une base en mémoire.

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

## Base de données (Drift / SQLite)

Un fichier `crochet_creations.sqlite` dans le stockage privé de l'application. Aucun serveur.

### Les 15 tables

| Table | Rôle |
|-------|------|
| `parametres_entreprise` | Profil « Mon entreprise » et réglages (mode jour/nuit). **Une seule ligne** (`id = 1`), créée automatiquement |
| `numerotation_documents` | Dernier numéro attribué par suite : factures et devis (une suite par année), références produit |
| `produits` | Catalogue : nom, catégorie, référence `PRD-0001`, matières, dimensions, temps de fabrication, coût, prix, stock, seuil, statut, « personnalisable », photo principale |
| `variantes_produit` | Couleur / taille d'un produit, avec stock et prix propres |
| `photos_produit` | Photos secondaires (la principale est dans `produits`) |
| `clients` | Particuliers et professionnels (civilité, coordonnées, SIREN/SIRET, notes) |
| `ventes` | Une vente : client (vide = « client de passage »), remise, frais de port, total, statut de paiement |
| `lignes_vente` | Produits, cours ou lignes libres d'une vente, avec nature `bien` / `service` pour les deux compteurs de chiffre d'affaires |
| `paiements` | Encaissements et remboursements (montant négatif) d'une vente, avec leur mode |
| `factures` | Facture émise à partir d'une vente : numéro `FACT-AAAA-NNNN`, coordonnées client et mention TVA recopiées |
| `devis` | Devis `DEVIS-AAAA-NNNN` : validité, délai, acompte, statut ; pointe vers la vente créée à la conversion |
| `lignes_devis` | Lignes libres, produits ou cours d'un devis |
| `cours` | Titre, date, durée, lieu, prix, places, niveau, matériel inclus, photo |
| `inscriptions_cours` | Inscription d'un client à un cours : confirmée ou en liste d'attente, vente qui l'encaisse |
| `depenses` | Date, catégorie, montant, fournisseur, photo du ticket, produit concerné |

Relations principales :

```
clients ──< ventes ──< lignes_vente >── produits ──< variantes_produit
              │  └──< paiements              └──< photos_produit
              ├──< factures                        ▲
devis ───────┘ (devis.vente_id)           depenses ┘ (produit concerné)
cours ──< inscriptions_cours >── clients       lignes_vente / lignes_devis >── cours
```

### Garanties apportées par la base elle-même

Même si le code se trompait, SQLite refuse :

- une liaison vers un élément inexistant, ou la suppression d'un élément encore utilisé (clés étrangères activées
  à chaque ouverture) ;
- un stock, une quantité ou un montant négatif ; un nom vide ; un paiement de 0 € ;
- un total qui n'est pas « sous-total − remise + frais de port », une remise supérieure au sous-total, un
  pourcentage au-delà de 100 %, un total de ligne différent de « quantité × prix » ;
- deux factures ou deux devis de même numéro, deux références produit identiques ;
- plus d'une facture **émise** par vente (une facture annulée n'empêche pas d'en émettre une nouvelle) ;
- un produit classé comme prestation, ou un cours classé comme objet ;
- un acompte supérieur au total d'un devis ; deux inscriptions du même client au même cours.

Les règles propres à chaque étape (par exemple « une vente facturée n'est plus modifiable ») sont ajoutées dans
les repositories de l'étape concernée.

### Numérotation

`NumerotationRepository` attribue `FACT-2026-0001`, `DEVIS-2026-0001`, `PRD-0001`. Il doit être appelé **dans la
transaction qui enregistre le document** : si l'enregistrement échoue, le numéro n'est pas consommé, donc pas de
trou dans la suite. Les suites facture et devis repartent à 1 chaque année (l'année figure dans le numéro).

### Code généré (build_runner)

Drift écrit lui-même une partie du code (`app_database.g.dart` : classes de lignes, requêtes typées). Ces fichiers
`*.g.dart` ne sont **pas versionnés** : ils se recréent avec

```bash
dart run build_runner build --delete-conflicting-outputs
```

La CI le fait automatiquement. En local, à relancer après chaque modification de `tables.dart`
(ou `dart run build_runner watch` pendant le développement).

### Faire évoluer le schéma (migrations versionnées)

1. Modifier `tables.dart` (par exemple ajouter une colonne).
2. Augmenter `AppDatabase.versionSchema` (1 → 2).
3. Dans `onUpgrade` (`app_database.dart`), ajouter le palier correspondant :
   `if (from < 2) { await m.addColumn(produits, produits.nouvelleColonne); }`.
   Les paliers s'exécutent dans l'ordre : une installation en version 1 passe par 2, puis 3…
4. Ajouter un test qui vérifie la nouvelle colonne, et relancer `build_runner`.

Les valeurs des listes de choix sont enregistrées sous leur **nom Dart** : ne jamais renommer une valeur de
`enums.dart` sans migration (un test, `enums_test.dart`, protège les noms cités dans les contraintes SQL).
Après une migration, `PRAGMA foreign_key_check` vérifie qu'aucune liaison n'a été cassée.

## Dossier `android/`

Le dossier `android/` n'est pas versionné. `tool/setup_android.sh` le crée avec `flutter create`,
règle le nom affiché (« Crochet & Créations ») et génère les icônes. La CI exécute ce script à chaque fois.

Conséquence à garder en tête pour les étapes suivantes : toute modification de configuration Android
(permissions caméra/photos pour `image_picker`, par exemple) devra être ajoutée à ce script.
Si cette contrainte gêne, on pourra versionner `android/` à la place (il suffit de retirer `/android/` du `.gitignore`).

## Choix techniques

| Sujet | Décision | État |
|-------|----------|------|
| Base de données | **Drift** (SQLite) : requêtes typées et vérifiées à la compilation, migrations versionnées, flux de données réactifs, base en mémoire pour les tests. Meilleur choix de maintenabilité parmi les deux options du cahier des charges | mis en œuvre à l'étape 2, à confirmer |
| Dépendances | `drift`, `drift_flutter` (ouverture du fichier), `path_provider` ; en développement `drift_dev` et `build_runner`. SQLite est embarqué automatiquement par le paquet `sqlite3` | étape 2 |
| Version minimale | Dart 3.10 / Flutter 3.38 (exigé par Drift 2.35) : utiliser le canal *stable* | étape 2 |
| Modèles | Classes de lignes générées par Drift, pas de seconde série d'entités | étape 2 |
| Mémorisation du mode jour/nuit | Dans la base (`parametres_entreprise`), sans bibliothèque supplémentaire | fait |
| Dépendances des étapes suivantes | `pdf`, `printing`, `share_plus`, `image_picker`… arriveront avec les étapes qui s'en servent | à venir |

### Hypothèses du schéma, à confirmer

Le cahier des charges ne tranchait pas ces points ; voici ce qui a été retenu (modifiable par une migration) :

- **Client de passage** : pas de fiche, `ventes.client_id` reste vide.
- **Stock** : porté par le produit, ou par chaque variante s'il en a. Un produit au statut « sur commande » n'est
  ni décrémenté ni vérifié.
- **Devis converti** : il crée une vente (`devis.vente_id`) ; la facture se fait ensuite depuis cette vente.
  « Commande » = vente validée non encore facturée.
- **Remboursement** : un paiement de montant négatif ; statut « remboursée » quand tout ce qui a été encaissé est rendu.
- **Niveaux de cours** : débutant, intermédiaire, avancé, tous niveaux. Un cours peut être « annulé ».
- **Profil entreprise** : en plus de la liste du cahier des charges, un champ « nom de l'entrepreneuse »
  (mention habituelle sur les factures). Conditions de paiement par défaut : « Paiement à réception de la facture. »
- **Chiffre d'affaires par nature** (objets / prestations) : chaque ligne porte sa nature ; la base de calcul exacte
  (encaissements ou factures, répartition de la remise et des frais de port) sera décidée à l'étape 10.
- **Annulation d'une facture** : un simple statut « annulée » ; l'avoir (facture rectificative) n'est pas géré en version 1.

## Tests

- `test/core/` : montants, dates, thèmes (couleurs de la charte et contrastes), mode d'affichage et sa mémorisation.
- `test/domain/` : total d'une vente (remise, frais de port, arrondis), statut de paiement, règles de stock,
  format des numéros, noms des listes de choix. Aucun accès à la base ni à l'interface.
- `test/data/` : sur une vraie base SQLite **en mémoire** (mêmes tables, index et contraintes que sur le téléphone) :
  structure et contraintes (`schema_test.dart`), numérotation continue et sans doublon, décrémentation du stock
  « tout ou rien », archivage, variantes, réglages.
- `test/widget_test.dart` et `test/presentation/` : parcours splash → accueil → réglages, écran d'erreur de démarrage.

Restent à écrire avec leur étape : conversion devis → facture (étape 7) et statistiques (étape 10).

Commandes : `dart run build_runner build --delete-conflicting-outputs`, puis `flutter analyze` et `flutter test`.
