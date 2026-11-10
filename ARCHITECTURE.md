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
| `domain` | Règles métier pures en Dart : listes de choix, totaux d'une vente, statut de paiement, règles de stock, format des numéros, règles des devis, des cours et des dépenses, calculs des statistiques. Aucune dépendance à Flutter ni à la base | rien |
| `data` | Base SQLite (Drift), migrations, repositories, fichiers (photos, PDF, sauvegardes) | `domain`, `core` |

Règles :

- Un écran ne parle **jamais** directement à la base : il passe par un *provider* Riverpod qui appelle un repository.
- La logique métier vit dans `domain` et se teste sans interface ni base de données (tests unitaires rapides).
- `core` regroupe ce qui est partagé et sans logique métier : thème, constantes, utilitaires, widgets génériques.
- **Modèles** : les classes de lignes générées par Drift (`Produit`, `Client`, `Vente`, `Facture`…) servent de
  modèles à toutes les couches. On n'a pas créé de seconde série de classes « métier » identiques : ce serait du
  code en double à maintenir. La couche `domain` contient les règles et les listes de choix, pas les entités.

## Arborescence (étape 8)

```
crochet-creations/
├── .github/workflows/android.yml     construction automatique : code généré, analyse, tests, APK
├── assets/
│   ├── fonts/                        Poppins (titres) + licence OFL
│   ├── icon/                         logo_source.png (logo fourni) et app_icon_foreground.png (généré, voir tool/generate_icons.py)
│   └── images/                       logo_application.png (logo de l'application), logo_entreprise.jpg (logo de l'entreprise, pour les PDF)
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
│   │   │   ├── money.dart                    formatEuros, lecture d'un montant saisi (centimes)
│   │   │   ├── date_fr.dart                  dates (longue et courte) et salutation en français
│   │   │   ├── duree.dart                    « 45 min », « 2 h 30 »
│   │   │   ├── recherche.dart                recherche sans majuscules ni accents
│   │   │   ├── validateurs.dart              règles des champs de formulaire (obligatoire, montant, entier…)
│   │   │   └── texte.dart                    nettoyage des saisies facultatives
│   │   └── widgets/                          logo de l'application, icônes de barre d'état, dialogues de confirmation, étiquette
│   ├── domain/
│   │   ├── enums.dart                        listes de choix (statuts, modes de paiement…)
│   │   ├── categories_produit.dart           clés et noms des catégories de départ, règles du nom d'une catégorie
│   │   ├── lieux_vente.dart                  lieux de départ, « Non renseigné », règles du nom d'un lieu de vente
│   │   ├── notes.dart                        catégories de notes de départ, « Sans catégorie », règles du nom, du titre et du texte d'une note
│   │   ├── erreurs.dart                      erreurs métier à message clair
│   │   ├── usage_historique.dart             « où apparaît cet élément » (ventes, factures, devis, inscriptions), en phrase
│   │   ├── regles_client.dart                règles de saisie d'une fiche client (e-mail, téléphone, code postal, SIRET)
│   │   ├── regles_entreprise.dart            SIREN, IBAN, informations manquantes pour facturer, textes par défaut
│   │   ├── regles_devis.dart                 validité, statut affiché (expiré), transitions de statut, contrôle des dates et de l'acompte
│   │   ├── regles_cours.dart                 places restantes, liste d'attente, refus d'inscription / de confirmation / d'archivage
│   │   ├── regles_depenses.dart              montant, date non future, mois et bornes de mois
│   │   ├── document_facture.dart             DocumentFacture : tout ce qui s'imprime sur une facture (sans PDF ni base)
│   │   ├── document_devis.dart               DocumentDevis : tout ce qui s'imprime sur un devis (réutilise les lignes et parties de la facture)
│   │   └── calculs/
│   │       ├── totaux.dart                   sous-total, remise, frais de port, total
│   │       ├── statut_paiement.dart          payée / partielle / impayée / remboursée
│   │       ├── panier.dart                   panier d'une vente : lignes, stock, remise, frais de port, paiement saisi
│   │       ├── stock.dart                    alerte de stock, produit « sur commande »
│   │       ├── statistiques.dart             argent encaissé par période, parts, marge, classements, niveaux de franchise de TVA
│   │       └── numero_document.dart          FACT-2026-0001, DEVIS-2026-0001, PRD-0001
│   ├── data/
│   │   ├── database/
│   │   │   ├── tables.dart                   les 20 tables (contraintes, index)
│   │   │   ├── app_database.dart             base, version du schéma, migrations
│   │   │   ├── flux_en_direct.dart           lecture « en direct » de plusieurs tables (observerTables)
│   │   │   └── app_database.g.dart           (généré par build_runner, non versionné)
│   │   ├── repositories/
│   │   │   ├── numerotation_repository.dart  FACT-…, DEVIS-…, PRD-…
│   │   │   ├── parametres_repository.dart    profil entreprise, mode jour/nuit
│   │   │   ├── produit_repository.dart       catalogue : créer, modifier, dupliquer, archiver, supprimer, stock, historique
│   │   │   ├── produit_vues.dart             ce que lisent les écrans : ProduitResume, ProduitDetail, historique
│   │   │   ├── categorie_repository.dart     catégories de produits : lister, créer, renommer, supprimer (en déplaçant les produits)
│   │   │   ├── lieu_vente_repository.dart    lieux de vente : lister, créer, renommer, supprimer (en déplaçant les ventes), ventes par lieu
│   │   │   ├── categorie_note_repository.dart catégories de notes : lister, créer, renommer, supprimer (en déplaçant les notes), notes par catégorie
│   │   │   ├── note_repository.dart          notes : lister, créer, modifier, supprimer, en direct
│   │   │   ├── client_repository.dart        clients : créer, modifier, archiver, supprimer, fiche et historique en direct
│   │   │   ├── client_vues.dart              nom affiché, initiales, historique d'un client (ventes, paiements, cours…)
│   │   │   ├── vente_repository.dart         ventes : valider, annuler, encaisser, changer le lieu, détail en direct
│   │   │   ├── vente_vues.dart               VenteDetail : vente, lignes, paiements, client, lieu, factures, solde dû
│   │   │   ├── facture_repository.dart       factures : créer (numéro + PDF), annuler, lister, obtenir le PDF
│   │   │   ├── devis_repository.dart         devis : créer, modifier, statuts, expiration, convertir, PDF
│   │   │   ├── devis_vues.dart               DevisResume, DevisDetail (statut affiché, actions possibles), ResultatConversion
│   │   │   ├── cours_repository.dart         cours : créer, modifier, annuler, archiver ; inscrire, confirmer, annuler une inscription
│   │   │   ├── cours_vues.dart               CoursResume, CoursDetail, InscriptionDetail (vente, paiement, facture, rang d'attente)
│   │   │   ├── depense_repository.dart       dépenses : créer, modifier, archiver, restaurer, lister par mois avec total
│   │   │   ├── depense_vues.dart             FiltreDepenses, DepenseLigne, ListeDepenses
│   │   │   ├── statistiques_repository.dart  statistiques : lecture des ventes, paiements, dépenses, factures impayées (lecture seule)
│   │   │   └── statistiques_vues.dart        Statistiques : les quatre périodes, factures impayées, chiffres de franchise
│   │   ├── pdf/
│   │   │   ├── elements_pdf.dart             éléments de mise en page communs aux factures et aux devis (en-tête, totaux, pied de page)
│   │   │   ├── facture_pdf.dart              mise en page du PDF d'une facture (genererFacturePdf)
│   │   │   ├── devis_pdf.dart                mise en page du PDF d'un devis (genererDevisPdf)
│   │   │   ├── construire_document.dart      facture ou devis + profil → DocumentFacture / DocumentDevis
│   │   │   └── ressources_pdf.dart           polices Poppins et logo lus dans les ressources
│   │   ├── partage/service_documents.dart    partage (share_plus) et impression (printing), remplaçables en test
│   │   ├── sauvegarde/
│   │   │   ├── format_sauvegarde.dart        contenu d'une archive (format 2), tables dans l'ordre, colonnes qui citent des fichiers, modèles de progression
│   │   │   ├── service_sauvegarde.dart       sauvegarder (en flux, avec empreintes), lister, sauvegarde automatique, restaurer (avec contrôle), export JSON
│   │   │   ├── espace_libre.dart             place libre du téléphone (interface + mesure Android par disk_space_plus)
│   │   │   ├── export_csv.dart               export CSV : un .zip, un fichier par type de données
│   │   │   └── selecteur_fichier.dart        choix du fichier à restaurer : copie de travail en flux (interface + sélecteur Android)
│   │   ├── partage/
│   │   │   └── service_partage_fichiers.dart partage d'un fichier quelconque (sauvegarde, export) par la feuille de partage
│   │   ├── stockage/
│   │   │   ├── stockage_photos.dart          copie les photos dans le dossier privé de l'application
│   │   │   ├── stockage_pdf.dart             range les PDF (factures, devis) : un fichier par numéro
│   │   │   ├── selecteur_photo.dart          choix d'une photo (galerie / appareil), remplaçable en test
│   │   │   ├── stockage_pieces_jointes.dart  range les pièces jointes des notes en flux, avec les limites de taille
│   │   │   ├── selecteur_piece_jointe.dart   choix d'une photo, d'une vidéo ou d'un document (interface + sélecteurs Android)
│   │   │   └── ouvreur_piece_jointe.dart     ouvre un fichier dans l'application du téléphone (interface + open_filex)
│   │   └── providers.dart                    accès Riverpod à la base, aux repositories, aux photos et à l'horloge
│   └── presentation/
│       ├── common/                   placeholder_screen.dart, menu_tile.dart, choix_photo.dart (feuille de choix de photo), photo_retrouvee.dart
│       ├── clients/                          onglet Clients et ses écrans (voir « Clients »)
│       │   ├── clients_screen.dart           liste, recherche, filtres (écran 6)
│       │   ├── client_fiche_screen.dart      fiche et historique d'un client (écran 7)
│       │   ├── client_form_screen.dart       ajout / modification
│       │   ├── filtres_clients.dart          recherche + filtres, et fonction de filtrage
│       │   ├── clients_providers.dart        flux Riverpod (liste, fiche, historique)
│       │   └── client_widgets.dart           pastille d'initiales, étiquettes, résumé des coordonnées
│       ├── cours/                            cours (voir « Cours et inscriptions »)
│       │   ├── cours_screen.dart             liste des cours : à venir, passés, archivés (écran 16)
│       │   ├── cours_fiche_screen.dart       fiche : inscrits, liste d'attente, actions sur une personne (écran 17)
│       │   ├── cours_inscription_screen.dart inscription ou confirmation d'une personne en attente (écran 18)
│       │   ├── cours_form_screen.dart        création / modification d'un cours
│       │   ├── cours_providers.dart          flux Riverpod (liste par filtre, fiche)
│       │   └── cours_widgets.dart            photo du cours, créneau, places, étiquettes de statut et de paiement
│       ├── sauvegarde/                       sauvegarde et export (voir « Sauvegarde et export »)
│       │   ├── sauvegarde_screen.dart        écran Sauvegarde et export : sauvegarder, restaurer, exporter (écran 23)
│       │   └── sauvegarde_providers.dart     liste des sauvegardes du téléphone
│       ├── statistiques/                     statistiques (voir « Statistiques »)
│       │   ├── statistiques_screen.dart      écran Statistiques : période, chiffres, classements (écran 20)
│       │   ├── franchise_tva_carte.dart      carte de franchise de TVA (accueil et statistiques)
│       │   └── statistiques_providers.dart   flux Riverpod des statistiques
│       ├── depenses/                         dépenses (voir « Dépenses »)
│       │   ├── depenses_screen.dart          liste du mois : total, catégories, archivées (écran 19)
│       │   ├── depense_form_screen.dart      création / modification, photo du ticket, produit concerné, archivage
│       │   ├── selecteur_produit.dart        choix du produit concerné (recherche, « Aucun produit »)
│       │   ├── depenses_providers.dart       flux Riverpod (liste par filtre)
│       │   └── depenses_widgets.dart         icônes de catégorie, photo du ticket
│       ├── devis/                            devis (voir « Devis »)
│       │   ├── devis_screen.dart             liste des devis (écran 13)
│       │   ├── devis_form_screen.dart        création / modification d'un devis (écran 14)
│       │   ├── devis_detail_screen.dart      détail, aperçu PDF, statut, partager, imprimer
│       │   ├── devis_conversion_screen.dart  conversion en commande, avec ou sans facture (écran 15)
│       │   ├── devis_providers.dart          flux Riverpod, PDF, clé de version de l'aperçu
│       │   └── devis_widgets.dart            étiquette de statut
│       ├── entreprise/
│       │   ├── mon_entreprise_screen.dart    profil « Mon entreprise » (écran 22)
│       │   └── profil_incomplet.dart         fenêtre « Informations manquantes » (factures, conversion de devis)
│       ├── factures/                         factures (voir « Factures PDF »)
│       │   ├── factures_screen.dart          liste des factures (écran 11)
│       │   ├── facture_detail_screen.dart    aperçu et détail : partager, imprimer, annuler (écran 12)
│       │   └── factures_providers.dart       flux Riverpod, PDF, aperçu remplaçable en test
│       ├── home/home_screen.dart             accueil / tableau de bord
│       ├── lieux/                            lieux de vente (voir « Lieux de vente »)
│       │   ├── lieux_screen.dart             Réglages › Lieux de vente : ajouter, renommer, supprimer (en déplaçant les ventes)
│       │   ├── lieu_dialogues.dart           boîte « nom de lieu de vente » (création et renommage)
│       │   ├── lieux_providers.dart          lieux en direct, nombre de ventes par lieu, recherche d'un lieu par identifiant
│       │   └── choix_lieu.dart               carte « Lieu de vente » et feuille de choix (panier, détail d'une vente)
│       ├── more/more_screen.dart             onglet « Plus »
│       ├── notes/                            bloc-notes (voir « Bloc-notes »)
│       │   ├── notes_screen.dart             Plus › Bloc-notes : liste, filtres par catégorie, « Nouvelle note »
│       │   ├── note_form_screen.dart         une note : titre, catégorie, texte, pièces jointes ; enregistrer, supprimer, abandonner
│       │   ├── pieces_jointes_section.dart   section « Pièces jointes » du formulaire, feuille d'ajout, visionneuse de photo
│       │   ├── categories_note_screen.dart   Réglages › Catégories de notes : ajouter, renommer, supprimer (en déplaçant les notes)
│       │   ├── categorie_note_dialogues.dart boîte « nom de catégorie de notes » (création et renommage)
│       │   ├── choix_categorie_note.dart     carte « Catégorie » et feuille de choix du formulaire d'une note
│       │   └── notes_providers.dart          notes en direct, catégories en direct, nombre de notes par catégorie
│       ├── produits/                         onglet Produits et ses écrans (voir « Produits et stock »)
│       │   ├── produits_screen.dart          liste, recherche, filtres (écran 3)
│       │   ├── produit_fiche_screen.dart     fiche d'un produit (écran 4)
│       │   ├── produit_form_screen.dart      ajout / modification (écran 5), avec « + Nouvelle catégorie »
│       │   ├── categories_screen.dart        Réglages › Catégories : ajouter, renommer, supprimer
│       │   ├── categorie_dialogues.dart      boîte « nom de catégorie » (création et renommage)
│       │   ├── categories_providers.dart     catégories en direct, noms par clé, nombre de produits par catégorie
│       │   ├── photos_formulaire.dart        photos en cours d'édition et fichiers à nettoyer
│       │   ├── variante_form_sheet.dart      feuille d'ajout / modification d'une variante
│       │   ├── stock_dialog.dart             « Ajuster le stock »
│       │   ├── filtres_produits.dart         recherche + filtres, et fonction de filtrage
│       │   ├── produits_providers.dart       flux Riverpod (résumés, détail, historique)
│       │   └── produit_widgets.dart          image, étiquettes, textes de stock et de prix
│       ├── router/app_router.dart            route → écran
│       ├── ventes/                           onglet Vente et ses écrans (voir « Ventes et panier »)
│       │   ├── vente_screen.dart             nouvelle vente : client, produits, barre du panier (écran 8)
│       │   ├── panier_screen.dart            panier, remise, frais de port, paiement, validation (écran 9)
│       │   ├── vente_confirmation_screen.dart  confirmation et détail d'une vente : encaisser, annuler (écran 10)
│       │   ├── panier_provider.dart          vente en cours (panier, client, note), conservée entre les écrans
│       │   ├── ajout_panier.dart             ajout d'un produit (choix de variante) ou d'une ligne libre (aussi pour les devis)
│       │   ├── selecteur_client.dart         choix du client ou « client de passage » (aussi pour les devis ; fiche obligatoire pour un cours)
│       │   ├── saisie_paiement.dart          rubrique « Paiement » : payée, acompte, plus tard, mode (panier et inscription)
│       │   ├── recap_widgets.dart            lignes de montant et cartes de rubrique
│       │   └── ventes_providers.dart         détail d'une vente en direct
│       ├── settings/settings_screen.dart     réglages (thème)
│       ├── shell/                            barre de navigation + onglet courant
│       ├── splash/splash_screen.dart         écran de démarrage
│       └── startup/erreur_demarrage_app.dart écran d'erreur si la base ne s'ouvre pas
├── test/
│   ├── core/ domain/ data/ presentation/     tests (voir plus bas)
│   └── widget_test.dart                      parcours splash → accueil → réglages
├── tool/
│   ├── generate_icons.py             logo fourni → premier plan d'icône adaptative et logo de l'application
│   ├── setup_android.sh              crée android/, règle le nom, prépare la signature, génère les icônes
│   ├── patch_signature_android.py    branche la clé de signature stable dans android/app/build.gradle.kts
│   ├── empreinte_signature_apk.py    lit la signature d'un APK (SHA-256 / SHA-1) et la compare à l'attendue
│   ├── signature_attendue.txt        empreinte SHA-256 attendue de la clé stable (publique)
│   ├── tests/                        tests Python des scripts de signature (modèle Gradle de Flutter en copie)
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
  Un **client** ou un **produit** peut en plus être **supprimé pour de bon**, même s'il a servi : on **détache** alors
  l'historique au lieu de le détruire (voir « Supprimer un client ou un produit » plus bas).

## Gestion d'état : Riverpod

`ProviderScope` entoure l'application (`main.dart`). États et accès actuels :

- `themeModeProvider` : mode d'affichage choisi (auto / jour / nuit). Il est **mémorisé** dans la table
  `parametres_entreprise` : `main()` le lit avant le premier écran (pas de clignotement) et chaque changement
  est enregistré en arrière-plan (`modeThemeInitialProvider`, `modeThemeStoreProvider`) ;
- `navIndexProvider` : onglet affiché, ce qui permet à l'accueil de basculer vers l'onglet Vente ;
- `appDatabaseProvider` et un provider par repository (`lib/data/providers.dart`). `appDatabaseProvider` est fourni
  par `main()` ; les tests le remplacent par une base en mémoire ;
- `stockagePhotosProvider` (dossier des photos, fourni par `main()`) et `selecteurPhotoProvider` (galerie / appareil
  photo). Le premier lève une erreur explicite s'il n'est pas fourni ; les tests remplacent les deux ;
- produits (`presentation/produits/produits_providers.dart`) : `produitsResumesProvider` (catalogue, en direct),
  `produitDetailProvider(id)` et `historiqueProduitProvider(id)` (fiche et historique, en direct),
  `nombreAReapprovisionnerProvider` (pastille de l'accueil et du filtre) ;
- catégories (`presentation/produits/categories_providers.dart`) : `categoriesProduitProvider` (liste en direct, dans l'ordre),
  `nomsCategoriesProvider` (nom par clé), `nombreProduitsParCategorieProvider` (écran Catégories) ;
- lieux de vente (`presentation/lieux/lieux_providers.dart`) : `lieuxVenteProvider` (liste en direct, dans l'ordre),
  `nombreVentesParLieuProvider` (écran Lieux de vente) ; `venteEnCoursProvider` porte aussi le lieu choisi dans le panier ;
- bloc-notes (`presentation/notes/notes_providers.dart`) : `notesProvider` (notes en direct, la dernière modifiée en premier),
  `categoriesNoteProvider` (catégories en direct, dans l'ordre), `nombreNotesParCategorieProvider` (écran Catégories de notes),
  `nombrePiecesJointesParNoteProvider` (liste des notes) ; les pièces jointes ont leurs propres providers dans `data/providers.dart`
  (`stockagePiecesJointesProvider`, `selecteurPieceJointeProvider`, `ouvreurPieceJointeProvider`), remplacés en test ;
- `filtresProduitsProvider` : recherche, catégorie (clé), « Archivés », « À réapprovisionner ». Il vit au-dessus des écrans :
  le filtre choisi depuis l'accueil (« Stock faible ») s'applique à l'ouverture de l'onglet Produits ;
- clients (`presentation/clients/clients_providers.dart`) : `clientsProvider` (tous les clients, archivés compris, en
  direct), `clientProvider(id)` (fiche) et `historiqueClientProvider(id)` (devis, ventes, factures, paiements, cours) ;
- `filtresClientsProvider` : recherche, type (particulier / professionnel), « Archivés ». Le filtrage et le tri
  se font côté écran (`filtrerClients`), sur la liste complète : un client archivé apparaît ou disparaît sans relecture ;
- sauvegarde (étape 11) : `serviceSauvegardeProvider` (fourni par `main()`, lève une erreur explicite sinon),
  `exportCsvProvider`, `selecteurFichierSauvegardeProvider` et `servicePartageFichiersProvider` (les tests remplacent
  les deux derniers par des faux), `sauvegardesLocalesProvider` (liste des sauvegardes du téléphone, relue par
  `ref.invalidate` après chaque sauvegarde, suppression ou restauration).

Les flux « en direct » sont des `StreamProvider.autoDispose` : l'écran se met à jour tout seul après chaque
enregistrement, sans rechargement manuel.

## Navigation

Navigation Flutter standard (`Navigator` + routes nommées), sans bibliothèque supplémentaire :

- `AppRoutes` liste les noms de routes ; `AppRouter.onGenerateRoute` les associe aux écrans ;
- `MainShell` porte la barre à 5 onglets (Accueil · Produits · Vente · Clients · Plus) avec `IndexedStack`,
  ce qui conserve l'état de chaque onglet (par exemple une vente en cours) quand on change d'onglet ;
- les autres écrans (factures, devis, cours…) s'ouvrent par-dessus, depuis *Plus* ou l'accueil ;
- les écrans qui concernent un élément précis reçoivent son identifiant en **argument de route**
  (`Navigator.pushNamed(context, AppRoutes.produitFiche, arguments: produit.id)`) ; `AppRouter` le lit et
  affiche un message d'erreur si l'identifiant manque. Aujourd'hui : `produitFiche`, `produitModifier`,
  `clientFiche`, `clientModifier`, `factureDetail`, `devisDetail`, `devisModifier`, `devisConversion`,
  `venteConfirmation`, `coursFiche`, `coursModifier` et `depenseModifier` ; `produitNouveau`, `clientNouveau`,
  `devisNouveau`, `coursNouveau` et `depenseNouvelle` n'en prennent pas ; `coursInscription` reçoit un `ArgumentsInscription` (cours et, pour confirmer une
  personne en attente, son inscription) ;
- « Vendre » et « Ajouter au panier » depuis une fiche produit ramènent à la racine et ouvrent l'onglet Vente
  (`navIndexProvider`) ; cet onglet reste un écran « Bientôt disponible » jusqu'à l'étape 5 ;
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
- **Nom et logo** : le nom affiché est `AppConstants.nomApplication` (« Un p’tit crochet dans les stocks ») ; le script
  `tool/setup_android.sh` écrit le même nom dans le manifeste Android (nom sous l'icône) et doit rester d'accord avec lui.
  Le logo est une image PNG fournie (`assets/icon/logo_source.png`, 1024 px) : `tool/generate_icons.py` en tire le
  premier plan de l'icône adaptative (logo réduit à 62 % pour rester dans la zone visible d'Android, bords estompés, fond
  `#FCE5E6` = couleur du pourtour du logo) et `assets/images/logo_application.png` (640 px), que le widget `AppLogo`
  affiche dans un carré aux coins arrondis. L'icône classique (Android avant 8) est le logo lui-même. Il n'y a plus de
  version monochrome de l'icône (thème d'icônes d'Android 13) ni de dépendance `flutter_svg`.
  Les factures et devis impriment `logo_entreprise.jpg` (logo de l'entreprise, JPEG, lu par `ressources_pdf.dart` et dessiné
  par `enteteDocument` dans `elements_pdf.dart`, 96 × 90 pt) ; le nom qu'ils portent est celui saisi dans *Mon entreprise*.

## Base de données (Drift / SQLite)

Un fichier `crochet_creations.sqlite` dans le stockage privé de l'application. Aucun serveur.

### Les 20 tables

| Table | Rôle |
|-------|------|
| `parametres_entreprise` | Profil « Mon entreprise » et réglages (mode jour/nuit). **Une seule ligne** (`id = 1`), créée automatiquement |
| `numerotation_documents` | Dernier numéro attribué par suite : factures et devis (une suite par année), références produit |
| `categories_produit` | Catégories de produits : clé interne stable, nom modifiable, ordre d'affichage |
| `produits` | Catalogue : nom, catégorie (clé de `categories_produit`), référence `PRD-0001`, matières, dimensions, temps de fabrication, coût, prix, stock, seuil, statut, « personnalisable », photo principale |
| `variantes_produit` | Couleur / taille d'un produit, avec stock et prix propres |
| `photos_produit` | Photos secondaires (la principale est dans `produits`) |
| `clients` | Particuliers et professionnels (civilité, coordonnées, SIREN/SIRET, notes) |
| `lieux_vente` | Lieux de vente (marché, salon, boutique, vente en ligne…) : nom modifiable, ordre d'affichage |
| `ventes` | Une vente : client (vide = « client de passage »), lieu (vide = « Non renseigné »), remise, frais de port, total, statut de paiement |
| `lignes_vente` | Produits, cours ou lignes libres d'une vente, avec nature `bien` / `service` pour les deux compteurs de chiffre d'affaires |
| `paiements` | Encaissements et remboursements (montant négatif) d'une vente, avec leur mode |
| `factures` | Facture émise à partir d'une vente : numéro `FACT-AAAA-NNNN`, coordonnées client et mention TVA recopiées |
| `devis` | Devis `DEVIS-AAAA-NNNN` : validité, délai, acompte, statut ; pointe vers la vente créée à la conversion |
| `lignes_devis` | Lignes libres, produits ou cours d'un devis |
| `cours` | Titre, date, durée, lieu, prix, places, niveau, matériel inclus, photo |
| `inscriptions_cours` | Inscription d'un client à un cours : confirmée ou en liste d'attente, vente qui l'encaisse |
| `depenses` | Date, catégorie, montant, fournisseur, photo du ticket, produit concerné |
| `categories_note` | Catégories du bloc-notes (Futures commandes, Documents entreprise, les vôtres) : nom modifiable, ordre d'affichage |
| `notes` | Une note : titre, texte, catégorie (vide = « Sans catégorie »), dates de création et de modification |
| `pieces_jointes_note` | Une pièce jointe d'une note : nom du fichier rangé, nom affiché, type (photo, vidéo, document), taille |

Relations principales :

```
clients ──< ventes ──< lignes_vente >── produits ──< variantes_produit
              │  └──< paiements              └──< photos_produit
              ├──< factures                        ▲
devis ───────┘ (devis.vente_id)           depenses ┘ (produit concerné)
cours ──< inscriptions_cours >── clients       lignes_vente / lignes_devis >── cours
categories_note ──< notes
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

Historique des versions du schéma : **1** (étapes 2 à 12), **2** (`ventes.client_nom` et `devis.client_nom`, pour garder le nom
d'un client supprimé), **3** (table `categories_produit`, remplie avec les cinq catégories de départ), **4** (table `lieux_vente`, remplie avec les quatre lieux de départ, et colonne `ventes.lieu_id` vide pour toutes les ventes existantes), **5** (tables `categories_note`, remplie avec les deux catégories de départ, et `notes`). Une sauvegarde d'un schéma plus ancien se restaure sans changement : la restauration n'écrit que les
colonnes présentes dans l'archive (voir « Restaurer »).

## Produits et stock (étape 3)

### Où est le stock ?

- Un produit **sans variante active** porte son stock (`produits.quantite_stock`) et son seuil d'alerte.
- Un produit **avec variantes actives** : le stock affiché est la **somme des variantes** ; le stock propre du
  produit est ignoré (le formulaire masque d'ailleurs ce champ). Une variante sans seuil hérite de celui du produit.
- Un produit **« sur commande »** n'est jamais suivi : pas de stock affiché, pas d'alerte, vendable à tout moment.
- Règles dans `domain/calculs/stock.dart` (`etatStockGlobal`, `alerteStock`, `suitLeStock`), testées sans base ;
  `ProduitResume` (couche `data`) les applique à un produit et ses variantes : `stockTotal`, `alerte`,
  `aReapprovisionner`, `vendable`.
- Alerte : **épuisé** si tout est à zéro ou si le statut est « épuisé » ; **stock faible** si au moins un article
  (produit ou variante) est au seuil ou en dessous.
- `ajusterStock` (± quantité : réapprovisionnement, correction) refuse un stock négatif ; `definirStock`
  (inventaire) fixe la quantité exacte ; `consommerStock` (vente, étape 5) retire les articles vendus et
  ne fait rien pour un produit « sur commande ».

### Lecture en direct des tables liées

`observerTables` (`data/database/flux_en_direct.dart`), utilisé par `ProduitRepository`, `ClientRepository` et
`VenteRepository`,
combine plusieurs tables sans bibliothèque supplémentaire :
`customSelect('SELECT 1 /* tables */', readsFrom: tables).watch().asyncMap((_) => lire())`. Dès qu'une des tables
change (produit, variante, photo, vente, client), la lecture complète est refaite et l'écran se met à jour.
Un produit et ses variantes sont ainsi toujours lus ensemble, jamais l'un sans l'autre.

⚠️ **Drift partage un même flux entre toutes les requêtes de même texte SQL, sans regarder les tables
surveillées.** Avec un `SELECT 1` identique partout, le premier flux ouvert (la liste des produits, toujours
affichée dans l'onglet Produits) « volait » les suivants, qui ne se rafraîchissaient plus quand une vente était
ajoutée. Les noms des tables sont donc écrits en commentaire dans le texte SQL : deux flux sur des tables
différentes ne se confondent plus (test `test/data/flux_en_direct_test.dart`).

### Photos

- `StockagePhotos` copie la photo choisie dans `<documents>/photos_produits` : la galerie peut être vidée sans
  perdre l'image. La base ne garde que le **nom du fichier** (un chemin absolu reste accepté tel quel).
- `SelecteurPhoto` est une interface : `SelecteurPhotoSysteme` utilise `image_picker` (images réduites à
  1 600 px, qualité 85 pour économiser l'espace) ; les tests utilisent un faux sélecteur.
- `PhotosFormulaire` suit les fichiers pendant l'édition : une photo ajoutée puis remplacée ou abandonnée est
  effacée aussitôt ; une photo déjà enregistrée n'est effacée **qu'après** l'enregistrement réussi.
- `creer` et `modifier` enregistrent produit, variantes et photos dans **une seule transaction** : tout ou rien.
- **Feuille « choix de photo » commune** (`presentation/common/choix_photo.dart`) : `demanderChoixPhoto` affiche la feuille
  du bas, `choisirFichierPhoto` va chercher le fichier (appareil, galerie ou photo retrouvée). Les formulaires des
  produits, des cours et des dépenses n'ont plus de code de choix de photo propre ; la copie dans l'application et le
  nettoyage restent faits par `PhotosFormulaire`.
- **Photo perdue** : quand Android ferme l'application pendant la prise de vue, `image_picker` garde la photo de côté.
  `main()` appelle **une seule fois** `SelecteurPhoto.retrouverPhotoPerdue()` (`retrieveLostData`, Android seulement ; toute
  erreur est notée dans le journal et ignorée) avant `runApp`, et passe le chemin retrouvé à `photoRetrouveeInitialeProvider`.
  `photoRetrouveeProvider` (`presentation/common/photo_retrouvee.dart`) le tient en mémoire : la feuille propose
  « Utiliser la photo retrouvée » tant que le fichier existe, puis l'oublie (`oublier()`) dès qu'on l'a utilisé ou qu'une
  autre photo est choisie. Le formulaire n'est pas restauré. Les tests règlent `EnvironnementTest.photoRetrouvee`.

### Règles de gestion retenues

- **Référence** : attribuée automatiquement (`PRD-0001`) dans la transaction de création, jamais modifiable.
- **Dupliquer** : nouvelle référence, nom suivi de « (copie) », variantes copiées avec un stock à 0, **sans photos** ;
  la copie s'ouvre en modification.
- **Archiver** : le produit disparaît du catalogue et ne peut plus être vendu, mais ses ventes passées restent
  lisibles ; « Restaurer » le remet (confirmation demandée avant d'archiver).
- **Supprimer** : voir « Supprimer un client ou un produit » plus bas.
- **Noms de variantes uniques** par produit, sans tenir compte des majuscules, **archivées comprises** (sinon la
  restauration créerait un doublon).
- **Historique** : lignes des ventes **validées** seulement (une vente annulée n'y figure pas), avec le client ou
  « Client de passage ». Vide tant que les ventes (étape 5) n'existent pas.
- **Vendable** : ni archivé, ni « épuisé », et stock > 0 sauf produit « sur commande ». Règle provisoire, à
  confirmer à l'étape 5.

### Catégories de produits modifiables

- **Une clé et un nom.** Chaque catégorie (`categories_produit`) a une **clé** interne qui ne change jamais et un **nom** que l'on
  modifie à volonté. `produits.categorie` enregistre la **clé**, jamais le nom : renommer une catégorie ne touche donc à aucun
  produit, et partout on affiche le nom actuel (`nomCategorie`, `nomsCategoriesProvider`). Les cinq catégories d'origine ont pour
  clés les anciens noms de l'enum (`crochet`, `doudou`, `bouclesOreilles`, `accessoire`, `surMesure`) : la migration ne modifie aucun
  produit et une ancienne sauvegarde se restaure telle quelle. Une catégorie créée reçoit une clé `cat_<heure en base 36>`.
- **Pas de clé étrangère SQL** de `produits.categorie` vers `categories_produit` : cela aurait obligé à reconstruire la table
  `produits` (la plus liée de la base) pour une migration sur des données réelles. L'intégrité est assurée par le code :
  `ProduitRepository` refuse une catégorie inconnue à la création et à la modification (`_verifierCategorie`), et
  `CategorieRepository.supprimer` déplace les produits **avant** de supprimer, dans la même transaction (tout ou rien). La table
  `categories_produit` impose elle-même un nom et une clé non vides et uniques.
- **Départ.** `AppDatabase.insererCategoriesDeDepart()` crée les cinq catégories (`INSERT OR IGNORE`) à la création de la base, à la
  migration 2 → 3 et à la restauration d'une sauvegarde qui n'a pas la table. Une base déjà au schéma 3 ne les recrée jamais : une
  catégorie d'origine supprimée ou renommée le reste.
- **Écrans.** Le formulaire produit propose les catégories puis « + Nouvelle catégorie » (la catégorie est créée tout de suite, même
  si le formulaire est abandonné ensuite) ; l'écran Réglages › Catégories ajoute, renomme et supprime. `demanderNomCategorie`
  (`categorie_dialogues.dart`) enregistre **dans** la boîte : un nom refusé reste affiché avec son explication. La suppression d'une
  catégorie utilisée ouvre une liste de destinations sans choix par défaut ; le nombre de produits est relu en base au moment de
  supprimer, et le filtre de la liste des produits est retiré si c'était cette catégorie.
- **Statistiques.** Les catégories rentables sont classées par marge ; à marge égale, l'ordre de la liste des catégories est conservé
  (`ordreCategories`), une clé qui n'y figure plus passe après, par clé. Une vente est comptée dans la catégorie **actuelle** du
  produit.

### Lieux de vente

- **Un lieu par vente, pas par document.** `ventes.lieu_id` enregistre l'**identifiant** du lieu, jamais son nom : renommer un lieu ne
  touche à aucune vente. Le lieu appartient à la **vente** ; ni la facture ni le devis n'en portent, donc une vente facturée n'est
  comptée qu'une fois dans un classement par lieu. Vide, il signifie « Non renseigné » (`libelleLieuNonRenseigne`) : c'est le cas
  de toutes les ventes d'avant la version 0.15.0 et de celles où l'on n'a rien choisi. Les anciennes ventes ne sont jamais
  rattachées à un lieu d'office.
- **Pas de clé étrangère SQL**, comme pour les catégories : ajouter une colonne `REFERENCES` à une table existante (`ventes`)
  obligerait à la reconstruire. L'intégrité est assurée par le code : `LieuVenteRepository.supprimer` déplace les ventes **avant**
  de supprimer, dans la même transaction (tout ou rien) ; le panier relit le lieu en base au moment de valider (un lieu supprimé
  entre-temps donne « Non renseigné », la vente n'est jamais bloquée) ; un identifiant orphelin s'affiche « Non renseigné ». La
  table impose elle-même un nom non vide, unique, de 60 caractères au plus.
- **Départ.** `AppDatabase.insererLieuxDeDepart()` crée Marché, Salon, Boutique et Vente en ligne (`INSERT OR IGNORE`, par nom) à
  la création de la base, à la migration 3 → 4 et à la restauration d'une sauvegarde sans la table. Une base déjà au schéma 4
  ne les recrée jamais : un lieu de départ supprimé ou renommé le reste. L'index `idx_ventes_lieu_id` est créé en SQL dans la
  migration.
- **Règles du nom** (`domain/lieux_vente.dart`) : non vide, 60 caractères au plus, espaces superflus retirés, pas deux lieux de même
  nom (sans tenir compte des majuscules, des accents ni des espaces), et pas « Non renseigné » (libellé d'une vente sans lieu).
  La boîte de saisie est partagée avec les catégories (`core/widgets/dialogue_nom.dart`) : l'enregistrement se fait **dans** la
  boîte, un nom refusé reste affiché avec son explication.
- **Supprimer un lieu.** Sans vente : une confirmation. Avec des ventes (annulées comprises) : une liste de destinations **sans choix
  par défaut** (les autres lieux, et « Non renseigné »), le bouton reste inactif tant qu'on n'a pas choisi ; le nombre de ventes
  est relu en base au moment de supprimer. Aucune vente n'est jamais supprimée ni modifiée autrement que par son lieu. On peut
  supprimer tous les lieux : les ventes passent alors en « Non renseigné ».
- **Où se choisit le lieu.** Dans le **panier**, avant de valider (`SelecteurLieu`, carte « Lieu de vente » → feuille du bas avec
  « Non renseigné », les lieux et « Nouveau lieu de vente », le lieu créé étant choisi aussitôt) ; et **après coup**, dans le détail
  d'une vente, même annulée (`VenteRepository.changerLieu` ne modifie que le lieu : ni montants, ni stock, ni paiements, ni
  facture).
- **Sauvegarde et exports.** `lieux_vente` est la 17e table de l'archive, placée **avant** `ventes` (`FormatSauvegarde.tables`) ;
  l'export CSV des ventes gagne une colonne « Lieu de vente » (le nom, « Non renseigné » si vide). Les statistiques par lieu viennent
  à une étape suivante : cette étape ne change aucun calcul.

### Bloc-notes

- **Une note** (`notes`) : un titre (obligatoire, 120 caractères au plus, espaces superflus retirés), un texte (facultatif ; seuls les
  blancs du début et de la fin sont retirés, les retours à la ligne du milieu restent) et une catégorie (facultative). `creeLe` et
  `modifieLe` viennent de la trace commune des tables ; **`modifieLe` n'est mis à jour que si quelque chose a changé** : ouvrir une note
  puis enregistrer sans rien changer ne la fait pas remonter dans la liste. Les notes sont lues `modifieLe` décroissant, puis `id`
  décroissant.
- **Une vraie clé étrangère.** Contrairement aux catégories de produits et aux lieux (qui touchent une table existante), `notes` est une
  table neuve : `notes.categorie_id` référence `categories_note.id` avec `ON DELETE RESTRICT`. Vide, il signifie « Sans catégorie »
  (`libelleSansCategorieNote`). La base refuse donc elle-même de supprimer une catégorie qui a encore des notes ; le code
  (`CategorieNoteRepository.supprimer`) déplace les notes **avant** de supprimer, dans la même transaction (tout ou rien).
  Les index `idx_notes_categorie_id` et `idx_notes_modifie_le` sont créés avec la table (et en SQL dans la migration).
- **Départ.** `AppDatabase.insererCategoriesNoteDeDepart()` crée « Futures commandes » et « Documents entreprise » (`INSERT OR IGNORE`,
  par nom) à la création de la base, à la migration 4 → 5 et à la restauration d'une sauvegarde sans la table. Une base déjà au
  schéma 5 ne les recrée jamais : une catégorie de départ supprimée ou renommée le reste.
- **Règles du nom d'une catégorie** (`domain/notes.dart`) : non vide, 60 caractères au plus, espaces superflus retirés, pas deux
  catégories de même nom (sans tenir compte des majuscules, des accents ni des espaces), et pas « Sans catégorie » (libellé d'une note
  sans catégorie). La boîte de saisie est la même que pour les catégories de produits et les lieux (`core/widgets/dialogue_nom.dart`,
  enveloppée par `demanderNomCategorieNote`) : un nom refusé reste affiché dans la boîte, avec son explication.
- **Supprimer une catégorie.** Sans note : une confirmation. Avec des notes : une liste de destinations **sans choix par défaut** (les
  autres catégories, et « Sans catégorie »), le bouton « Déplacer et supprimer » reste inactif tant qu'on n'a pas choisi ; le nombre de
  notes est relu en base au moment de supprimer. Déplacer des notes ne change pas leur date de modification. Aucune note n'est jamais
  supprimée par la suppression d'une catégorie. On peut supprimer toutes les catégories : les notes passent alors en « Sans catégorie ».
- **Supprimer une note** est **définitif** (confirmation dans l'écran de la note) : il n'y a pas de corbeille.
- **Trois notions à ne pas confondre** : le *lieu de vente* (où une vente a eu lieu), la *catégorie de produit* (le rangement du
  catalogue) et la *catégorie de note* (le rangement du bloc-notes) sont trois listes indépendantes, avec chacune son écran.
- **L'écran Bloc-notes** (`NotesScreen`) : filtres Toutes / chaque catégorie / Sans catégorie ; si la catégorie choisie comme filtre est
  supprimée, la liste revient à « Toutes ». Le formulaire (`NoteFormScreen`) suit le modèle des autres formulaires : champs validés,
  « Enregistrer » en haut, confirmation avant d'abandonner une saisie, catégorie choisie dans une feuille du bas qui propose aussi
  « Nouvelle catégorie » (créée et choisie aussitôt).
- **Sauvegarde et exports.** `categories_note` puis `notes` sont les deux dernières tables de l'archive (`FormatSauvegarde.tables`,
  ordre des clés étrangères). Les notes ne font pas partie des exports CSV pour l'instant. Pièces jointes et recherche : étapes
  suivantes du plan, rien n'est prévu dans cette étape.

## Clients (étape 4)

### Pièces jointes des notes

- **Une table, un dossier.** `pieces_jointes_note` (schéma **6**) : `note_id` (clé étrangère vers `notes`, **`ON DELETE CASCADE`**),
  `nom_fichier` (**unique** : un fichier n'appartient qu'à une pièce jointe), `nom_affiche` (le nom d'origine, 120 caractères au plus),
  `type_fichier` (`photo`, `video` ou `document`, contrainte `CHECK`), `octets` et `cree_le`. Les fichiers sont rangés dans
  `<documents>/notes_pieces_jointes`. Comme pour les photos, la base ne garde **que des noms** : `StockagePiecesJointes.fichier` ramène
  tout nom à son dernier morceau, rien ne peut faire sortir du dossier. L'index `idx_pieces_jointes_note_note_id` est créé avec la
  table, et en SQL dans la migration 5 → 6.
- **Limites** (`domain/pieces_jointes.dart`, affichées dans le formulaire et dans la feuille d'ajout) : **25 Mo** par photo et par
  document, **150 Mo** par vidéo, **20 pièces jointes** par note. Le type vient de la **source** pour les photos et les vidéos
  (appareil ou galerie) ; pour « Choisir un document », il est déduit de l'extension (`typePieceJointeDepuisNom` : une image choisie comme
  document est reconnue comme photo, une vidéo comme vidéo, le reste est un document). Un fichier vide est refusé.
- **Ranger sans passer par la mémoire.** `StockagePiecesJointes.enregistrer` copie le fichier choisi **en flux** (`FichierChoisi.lire`)
  dans un `.tmp`, puis le renomme sous un nom unique (`piece_<horloge>_<n>.<extension sûre>`). La taille est contrôlée **deux fois** : celle
  que le sélecteur annonce (refus avant de copier un octet) et celle qu'on constate en copiant (refus dès la limite dépassée, quand
  le sélecteur ne la donne pas). Dans tous les cas d'échec (limite, lecture, disque plein) le `.tmp` est effacé ; un disque plein
  donne un message clair.
- **Le formulaire garde la main jusqu'à « Enregistrer ».** Les pièces ajoutées sont copiées tout de suite (la personne les voit), mais
  `NoteRepository.creer/modifier` ne les écrit en base qu'à l'enregistrement, **dans la même transaction** que la note (tout ou rien :
  trop de pièces ou une pièce trop grosse annulent aussi la note). Les pièces **retirées** ne sont effacées du téléphone
  qu'**après** l'enregistrement ; si on abandonne, on efface les copies des pièces ajoutées, et seulement elles. Supprimer une note
  supprime ses lignes (cascade) puis ses fichiers.
- **Ouvrir.** Une **photo** s'affiche en plein écran dans l'application (`PhotoJointeScreen`, zoom). Une **vidéo** ou un **document**
  s'ouvre dans l'application du téléphone qui sait le lire (`OuvreurPieceJointe`, paquet gratuit `open_filex`) : on évite ainsi un
  lecteur de vidéo intégré, lourd dans l'APK. Sans application adaptée, un message le dit.
- **Sauvegarde.** `notes_pieces_jointes` est le 4e dossier de l'archive ; `pieces_jointes_note.nom_fichier` est déclarée dans
  `FormatSauvegarde.colonnesFichiers` comme **irremplaçable** : un fichier absent rend la sauvegarde **incomplète**. Les fichiers
  provisoires (`.tmp`) ne sont jamais archivés. Une archive faite avant l'étape 4 (schéma 5, sans la table) se restaure : aucune pièce jointe.
  Une vidéo n'est ni recompressée ni lue d'un bloc : l'archive et la restauration travaillent déjà en flux (étape 3).

### Règles de gestion retenues

- **Un nom suffit** : une fiche doit avoir au moins un prénom, un nom ou une raison sociale ; tout le reste est facultatif.
- **Nom affiché** (`libelleClient`) : la raison sociale pour un professionnel qui en a une (la personne à contacter
  s'affiche dessous), sinon « Prénom Nom ». La liste est triée sur ce nom, sans tenir compte des accents ni des
  majuscules, puis par ordre de création.
- **Raison sociale et SIREN/SIRET** n'existent que pour un professionnel : le formulaire les masque pour un
  particulier et ne les enregistre pas (repasser de Professionnel à Particulier les efface).
- **Règles de saisie** (`domain/regles_client.dart`), appliquées par le formulaire **et** par `DonneesClient.valider()` :
  une fiche refusée à l'écran l'est aussi par le dépôt de données, avec le même message. Elles contrôlent la **forme**
  seulement : e-mail `nom@domaine.ext`, téléphone de 6 à 15 chiffres (espaces et `+ ( ) . - /` acceptés), code postal de
  3 à 10 caractères (lettres, chiffres, espace, tiret : adresses étrangères acceptées), SIREN à 9 chiffres ou SIRET à 14
  (espaces et points acceptés). Aucun contrôle de l'existence du numéro ni de sa clé.
- **Archiver** : le client disparaît de la liste (filtre « Archivés » pour le retrouver), mais ses ventes, factures et
  devis restent liés à lui et lisibles.
- **Supprimer** : voir « Supprimer un client ou un produit » plus bas (les clés étrangères `ON DELETE RESTRICT` restent la
  garantie de la base : le code détache d'abord l'historique, puis supprime).
- **Client de passage** : pas de fiche, `ventes.client_id` reste vide ; il se choisit au moment de la vente (étape 5).

### Supprimer un client ou un produit

`ClientRepository.supprimer` et `ProduitRepository.supprimer` : une **transaction** chacune. L'historique n'est pas détruit,
il est **détaché** de la fiche supprimée. Les clés étrangères restent en `RESTRICT` : c'est le code qui défait les liens avant
de supprimer, la base refuserait tout oubli.

| | Client | Produit |
|--|--------|---------|
| Refus | inscrit à un cours : `SuppressionImpossible` (`inscriptions_cours.client_id` est obligatoire) | aucun |
| Ventes | `client_id` vidé, **`client_nom` = nom affiché** copié | lignes : `produit_id` et `variante_id` vidés (la désignation, la quantité et le prix y sont déjà) |
| Devis | idem (`client_id` vidé, `client_nom` copié) | lignes de devis : idem |
| Factures | `client_id` vidé seulement : nom, adresse et SIRET ont été copiés à l'émission | — |
| Dépenses | — | `produit_id` vidé (la dépense reste) |
| Fiche | supprimée | supprimée avec ses variantes et ses photos ; les **fichiers** de photos sont rendus à l'appelant, qui les efface une fois la transaction réussie |

- **Le nom copié** (`ventes.client_nom`, `devis.client_nom`, schéma 2) n'est renseigné qu'à la suppression du client ; il suit le
  devis converti en commande (`VenteRepository.valider(clientNom: …)`), puis la facture (`FactureRepository.creer`). Modifier
  un devis en lui donnant un autre client efface l'ancien nom. À l'affichage, `nomClientOuCopie` donne la fiche, sinon
  « Nom (client supprimé) », sinon « Client de passage » / « Sans client ». L'export CSV et le PDF de devis suivent la même règle
  (le PDF imprime le nom sans la mention « client supprimé »).
- **`usage(id)`** (`UsageHistorique`) compte ce qui apparaît dans l'historique, pour la phrase de la confirmation ; la
  confirmation est **renforcée** dès qu'il y a de l'historique. Un produit est compté par **ventes et devis distincts** (deux
  lignes d'une même vente comptent une fois), variantes comprises.
- **Écrans** : `_supprimer` des fiches client et produit (`confirmer` / `informer`, `dialogues.dart`). Pour un client inscrit à
  un cours, la boîte propose d'archiver à la place.
- Les numéros de référence d'un produit supprimé ne sont **pas réutilisés** (le compteur ne revient jamais en arrière).

### Historique d'un client

`ClientRepository.historique(id)` réunit, du plus récent au plus ancien :

- les **devis** et les **factures** liés au client (`client_id`) ;
- ses **ventes** (`VenteClient`), dont le total n'additionne que les ventes **validées** : une vente annulée est
  listée, marquée « Annulée », mais ne compte pas dans « N ventes validées · total » ;
- ses **paiements**, retrouvés par la vente (jointure `paiements` → `ventes`) : un remboursement a un montant négatif ;
- ses **inscriptions aux cours** (jointure avec `cours` pour le titre et la date), liste d'attente comprise.

`observerHistorique` relit le tout dès qu'une de ces tables change (même technique que le catalogue :
`observerTables`, voir « Lecture en direct des tables liées »). La fiche s'ouvre donc déjà à jour quand
les ventes, factures, devis et cours sont créés : aucun changement d'écran à prévoir.

## Ventes et panier (étape 5)

### La vente en cours

`venteEnCoursProvider` (`presentation/ventes/panier_provider.dart`) garde le panier, le client et la note de la
vente en cours : on peut passer de l'onglet Vente au panier, ou à une fiche produit, sans rien perdre. Il se vide
quand la vente est validée. Le panier lui-même (`domain/calculs/panier.dart`) est **immuable** : chaque changement
retourne un nouveau panier, ou lance une erreur métier (le panier reste alors inchangé).

### Règles du panier

- **Stock** : la quantité d'un article suivi en stock ne dépasse jamais le stock lu au moment de l'ajout
  (`StockInsuffisant`, message clair). Un produit « sur commande » n'a pas de limite. Une ligne libre n'est jamais
  limitée et ne touche jamais au stock.
- **Un produit à variantes se vend par variante** : le panier tient une ligne par produit **et** variante ; la
  désignation est « Produit – Variante ».
- **Remise** : en pourcentage (centièmes de pour cent : 1000 = 10 %) ou en centimes, jamais supérieure au
  sous-total ; frais de port ajoutés après la remise : total = sous-total − remise + frais de port
  (les mêmes formules que `domain/calculs/totaux.dart`, que la base contrôle aussi).
- **Paiement saisi** (`PaiementSaisi`) : un mode et un montant, jamais supérieur au total. À l'écran : « Payée »
  (tout), « Acompte » (une partie) ou « Plus tard » (rien).

### Valider, encaisser, annuler (`VenteRepository`)

- **`valider`** : une **transaction** unique. Contrôles (panier non vide, client existant et non archivé, produit
  existant, non archivé, non « épuisé », variante active ; un produit à variantes exige une variante), sortie de stock,
  vente, lignes (avec le coût matière du moment, utile aux statistiques de l'étape 10), paiement éventuel, calcul du
  statut de paiement. Au moindre échec, **rien** n'est enregistré, stock compris.
- **`encaisser`** : ajoute un paiement à une vente non annulée, dans la limite du solde dû. Le statut de paiement est
  recalculé à partir de **tous** les paiements (`calculerStatutPaiement`), jamais modifié à la main.
- **`annuler`** : remet le stock des articles suivis, enregistre un **remboursement** (paiement négatif) égal au net
  encaissé, avec le mode du dernier paiement, marque la vente « annulée » et les factures émises « annulées ». Une
  vente annulée reste visible dans l'historique et ne compte plus dans les totaux d'un client. Annuler deux fois est
  refusé.
- Une vente **validée ne se modifie pas** : on l'annule et on la refait.

### Facture à la demande

Aucun numéro de facture n'est attribué à la vente : il l'est quand on appuie sur « Créer la facture » (voir
« Factures PDF »).

### Où retrouver une vente

Par l'historique d'une fiche client ou d'une fiche produit (appui sur la ligne) : les deux ouvrent
`VenteConfirmationScreen`, qui sert donc aussi de détail d'une vente passée. `VenteRepository.observerDetail`
(`observerTables` sur ventes, lignes, paiements, clients et factures) la tient à jour pendant qu'on encaisse, qu'on
annule ou qu'on crée une facture.
Pas de liste générale des ventes pour l'instant.

## Factures PDF (étape 6)

### Créer une facture (`FactureRepository.creer`)

1. **Profil d'abord** : `informationsManquantes` (domain) compare « Mon entreprise » à ce qu'exige une facture (nom,
   adresse, code postal et ville, SIREN valide). S'il manque quelque chose : `ProfilIncomplet` (message listant
   l'élément manquant), et **aucune** écriture, donc aucun numéro consommé.
2. **Une transaction** : contrôle de la vente (existe, non annulée, pas déjà facturée), réservation du numéro par
   `NumerotationRepository.prochainNumeroFacture` (dans la même transaction : si l'insertion échoue, le numéro n'est
   pas consommé), enregistrement de la facture avec le client, la mention TVA, les conditions, l'IBAN et le
   remerciement **recopiés**. Un index unique partiel (`idx_factures_vente_emise`) garantit une seule facture émise
   par vente, même si deux appuis arrivent presque en même temps.
3. **Le PDF, après l'enregistrement** : `construireDocumentFacture` rassemble les données dans un
   `DocumentFacture`, `genererFacturePdf` fabrique le PDF, `StockagePdf` le range (`FACT-2026-0001.pdf`,
   écrit dans un fichier provisoire puis renommé) et le nom du fichier est noté dans `factures.pdf_chemin`. Si cette
   étape échoue, la facture existe quand même (la comptabilité d'abord) et `obtenirPdf` refabrique le PDF à la demande.

Les lignes et les montants ne sont pas recopiés : on les relit dans la vente liée, qui n'est plus modifiable.
Le profil de l'entreprise (nom, adresse, SIREN, téléphone, e-mail) n'est pas recopié non plus : un PDF refabriqué
plus tard utilise les coordonnées *actuelles*.

### Annuler une facture

`FactureRepository.annuler` change seulement le statut en « annulée » : le numéro reste utilisé (pas de trou, pas de
réutilisation), la vente n'est pas touchée et l'index unique partiel autorise une nouvelle facture pour la même vente.
Annuler une **vente** (`VenteRepository.annuler`) marque toujours ses factures émises « annulées ». Il n'y a pas
d'avoir (note de crédit) : voir les limites dans le CHANGELOG.

### Le PDF

`genererFacturePdf(DocumentFacture, RessourcesPdf)` ne lit aucun fichier : les polices et le logo lui sont
fournis (`chargerRessourcesPdf` en production, lecture directe du dossier `assets/` dans les tests). A4, marges de
42 pt, fond blanc, `MultiPage` (en-tête du tableau répété, bloc des totaux et des mentions d'un seul tenant, pied de
page paginé). Les tests fabriquent trois PDF d'exemple dans `build/exemples_pdf/` ; la CI les joint à la
pré-version de l'APK pour contrôler la mise en page à l'œil.

### Écrans

- `FacturesScreen` (liste), `FactureDetailScreen` (aperçu + actions) ; `facturePdfProvider` lit ou refabrique le PDF.
- L'aperçu (`PdfPreview` du paquet `printing`) est derrière `constructeurApercuPdfProvider`, le partage et l'impression
  derrière `serviceDocumentsProvider` : les tests les remplacent (le moteur d'impression et la feuille de partage sont
  ceux d'Android). Le fabricant de PDF (`generateurFacturePdfProvider`) est lui aussi remplaçable.
- `VenteConfirmationScreen` affiche la rubrique « Facture » : la facture en cours (qui s'ouvre) ou « Créer la
  facture ». Si le profil est incomplet, une fenêtre dit ce qui manque et propose d'ouvrir « Mon entreprise ».

## Devis (étape 7)

### Règles (`domain/regles_devis.dart`)

Des fonctions pures, testées sans base : `dateValiditeParDefaut` (émission + 30 jours calendaires), `validiteDepassee`,
`statutAffiche` (un devis brouillon ou envoyé dont la validité est dépassée s'affiche « expiré »), `statutsPossibles`
(brouillon → envoyé, accepté ou refusé ; envoyé → accepté ou refusé ; accepté non converti → refusé ; refusé, expiré
et devis déjà converti : aucun), `peutEtreModifie` (brouillon, envoyé, expiré ; pas un devis converti), `peutEtreConverti`
(brouillon, envoyé, accepté ; pas un devis déjà converti) et `verifierDevis` (validité ni avant l'émission ni déjà
passée, acompte entre 0 et le total).

### Le dépôt (`DevisRepository`)

- **Créer / modifier** : lignes, remise et frais de port viennent d'un `Panier` (lignes libres), avec un client
  facultatif, une date de validité, un délai de réalisation, un acompte et des notes. Le numéro **DEVIS-AAAA-NNNN**
  est réservé dans la même transaction que l'enregistrement. Modifier un devis expiré avec une validité future le
  remet « brouillon ».
- **Expiration** : `actualiserExpirations` enregistre « expiré » pour les devis brouillon ou envoyé périmés. Elle est
  appelée à l'ouverture de la liste, et **avant** toute transaction qui peut échouer (modifier, changer le statut,
  convertir), sinon l'annulation de la transaction effacerait aussi l'expiration.
- **Convertir** (`convertir`) : on vérifie d'abord que le devis est convertible et, si une facture est demandée, que
  « Mon entreprise » est complet (`FactureRepository.verifierProfil`) : sinon rien n'est écrit. Une transaction crée la
  vente par `VenteRepository.valider` (lignes libres, donc sans effet sur le stock ; remise et frais de port du devis ;
  note « Commande issue du devis N »), puis le premier paiement si « Acompte reçu » (montant de l'acompte, mode au
  choix), puis passe le devis à « accepté » et le relie à la vente (`devis.vente_id` : c'est ce lien qui le marque « converti »,
  il n'existe pas de statut « converti »). La facture est créée **après** cette
  transaction : si elle échoue, la commande existe et `ResultatConversion.problemeFacture` le dit.
- **Consulter** : `lister` (`DevisResume`), `detail` (`DevisDetail` : statut affiché à l'instant donné, actions
  possibles), flux en direct par `observerTables`.

### Le PDF

`genererDevisPdf(DocumentDevis, RessourcesPdf)` partage ses éléments avec la facture (`data/pdf/elements_pdf.dart` :
en-tête, parties, tableau, totaux, mention 293 B, pied de page). Spécifique au devis : « Établi le » et « Valable
jusqu'au », conditions (validité, délai, acompte, IBAN) **à gauche des totaux**, puis le cadre « Bon pour accord ».
Le PDF est rangé dans `<documents>/devis/` (`StockagePdf`) et refait quand le contenu imprimé change : la clé de
version de l'aperçu (`versionPdfDevis`) est calculée sur ce contenu, pas sur la date de modification, donc changer
le statut ne le refait pas.

### Écrans

`DevisScreen` (liste), `DevisFormScreen` (création et modification, abandon confirmé), `DevisDetailScreen` (aperçu,
statut, partager, imprimer, modifier, convertir), `DevisConversionScreen` (deux boutons, case « Acompte reçu »). Le
fabricant de PDF (`generateurDevisPdfProvider`), l'aperçu et le partage sont remplaçables en test comme pour les
factures.

## Cours et inscriptions (étape 8)

### Règles (`domain/regles_cours.dart`)

Des fonctions pures, testées sans base : `finDuCours` / `coursTermine`, `placesRestantes` (jamais négatif),
`statutNouvelleInscription` (place libre → confirmée, sinon liste d'attente), `ordreAttente` / `premierEnAttente`
(par date d'inscription, puis par identifiant), `verifierCours` (titre, durée d'au moins 1 minute, prix non négatif, au
moins une place, jamais moins de places que de personnes confirmées), `refusInscription` (cours annulé ou archivé),
`refusConfirmation` (pas en attente, cours complet, pas la première personne), `peutAnnulerInscription` et
`refusArchivage` (seul un cours terminé ou annulé s'archive). Chaque refus est une phrase française prête à afficher.

### Le dépôt (`CoursRepository`)

- **Inscrire** : une transaction vérifie le cours et le client, refuse les doublons, puis **s'il reste une place**
  crée la vente (`_creerVente` : un `Panier` d'une ligne « Cours : titre », nature service, `coursId`, description
  « Le jj/mm/aaaa à H h MM · durée X · lieu », notes « Inscription au cours « titre » », paiement éventuel, passage par
  `VenteRepository.valider`) et enregistre l'inscription « confirmée » reliée à la vente. Sinon l'inscription est
  « liste d'attente », sans vente, et un paiement est refusé. Le prix convenu est enregistré dans l'inscription.
  Une inscription annulée est réutilisée à la réinscription (clé unique cours + client).
- **Confirmer** : réservé à la première personne en attente quand une place est libre ; crée la vente au prix convenu
  et passe l'inscription à « confirmée ».
- **Annuler une inscription** : `rembourser: true` annule la vente (le net encaissé est remboursé par
  `VenteRepository.annuler`) ; `rembourser: false` ne touche à rien quand de l'argent a été reçu. Une vente sans
  encaissement est annulée dans les deux cas. Une place confirmée qui se libère n'est donnée à personne.
- **Consulter** : `lister` (filtres `FiltreCours`), `detail` (inscrits, liste d'attente numérotée, annulées, avec
  client, vente, net encaissé et facture), flux en direct par `observerTables`.

### Lien avec les ventes

`lignes_vente.cours_id` (clé étrangère vers `cours`) est renseigné par `Panier`/`VenteRepository.valider` ; la contrainte
de la base impose qu'une ligne de cours soit une prestation sans produit. Le chiffre d'affaires « prestations » de
l'étape 10 s'appuiera sur cette nature. La facture d'une inscription se crée depuis sa vente, comme toute facture.

### Écrans

`CoursScreen` (liste, filtres), `CoursFicheScreen` (informations, rubriques de personnes, feuille d'actions, dialogues
d'annulation à choix), `CoursInscriptionScreen` (inscription ou confirmation, avec `SaisiePaiement`), `CoursFormScreen`
(création / modification, photo gérée par `PhotosFormulaire`, abandon confirmé). L'écran d'inscription reçoit un
`ArgumentsInscription` (cours, et inscription à confirmer le cas échéant).

## Dépenses (étape 9)

### Règles (`domain/regles_depenses.dart`)

Des fonctions pures, testées sans base : `verifierDepense` (montant supérieur à 0, date jamais dans le futur, longueur du
fournisseur et de la description), `dateDansLeFutur` (comparaison par **jour** : la date du jour est permise), `jourDe`,
`debutDuMois` / `debutDuMoisSuivant`, `estDansLeMois` et `totalCentimes`. Chaque refus est une phrase française prête à
afficher.

### Le dépôt (`DepenseRepository`)

- **Créer / modifier** : valide les règles, vérifie que le produit concerné existe encore, enregistre la date à minuit
  (heure locale) et nettoie les textes (champ vide = rien). Le produit concerné est une **information** : le dépôt ne
  touche ni au coût matière ni au stock.
- **Archiver / restaurer** : colonne `archive_le` (suppression douce, comme les produits et les cours) ; une dépense
  archivée quitte la liste et les totaux mais peut encore être modifiée et restaurée.
- **Lister** : `lister(annee, mois, categorie?, archivees)` joint les produits (jointure externe) et retourne une
  `ListeDepenses` : les lignes, la plus récente d'abord, et le **total des lignes retournées** (donc celui de la catégorie
  quand on filtre). `observerListe` suit les tables `depenses` et `produits` en direct (`observerTables`).
- `FiltreDepenses` est un *record* Dart (année, mois, catégorie, archivées) : deux filtres identiques sont égaux, ce qui
  sert de clé à `depensesListeProvider`.

### Écrans

`DepensesScreen` (sélecteur de mois sans mois à venir, carte de total, pastilles de catégorie, icône d'archive pour passer aux dépenses archivées),
`DepenseFormScreen` (création / modification, photo gérée par `PhotosFormulaire` comme pour les cours, abandon confirmé,
menu d'archivage / restauration) et `LigneChoixProduit` / `FeuilleChoixProduit` (catalogue en feuille du bas).
La feuille « Prendre une photo / Galerie / Retirer » est dans `presentation/common/choix_photo.dart`, commune aux
formulaires des produits, des cours et des dépenses (voir *Photos*).

## Statistiques (étape 10)

### Calculs (`domain/calculs/statistiques.dart`)

Des fonctions pures, testées sans base. Le chiffre d'affaires est l'**argent encaissé** : `calculerStatsPeriode` parcourt les
ventes (annulées comprises : un remboursement compte) et ne retient que les paiements dont la date est dans la période
`[début, fin[`. Chaque encaissement est partagé entre les **éléments de la vente** (`composantsDeVente` : les lignes, avec
leur part de remise, et les frais de port comptés comme un objet) **au prorata de leur valeur** par
`repartirProportionnellement` (méthode du plus fort reste : la somme des parts est exactement le montant, aussi pour un
remboursement). La part de chaque élément alimente les compteurs objets / prestations / cours et sa catégorie de produit ;
le **coût de matière** (coût unitaire relevé à la vente × quantité) est imputé dans la même proportion
(`diviserArrondi`). Le panier moyen et les meilleures ventes, eux, se calculent sur les ventes **validées dont la date est
dans la période**. `bornesPeriode` donne le début et la fin de la période qui contient « maintenant » (semaine du lundi) ;
`niveauFranchise` donne `ok`, `approche` (≥ 80 % du seuil) ou `depasse` (strictement au-dessus).

### Le dépôt (`StatistiquesRepository`)

Lecture seule. `calculer` charge les paiements depuis la plus ancienne date utile (le 1er janvier, ou le lundi de la semaine
en cours s'il tombe en décembre), les ventes faites depuis ou payées depuis, leurs lignes (avec la catégorie du produit), les
dépenses **non archivées**, puis calcule **les quatre périodes en une passe**. Les **factures impayées** sont les factures
`emise` dont la vente (non annulée) a un solde dû > 0 (une vente comptée une fois). `observer` suit les tables `ventes`,
`lignes_vente`, `paiements`, `depenses`, `factures` et `produits` en direct (`observerTables`) ; l'heure vient de
`horlogeProvider` (remplaçable en test).

### Écrans

`statistiquesProvider` (un flux partagé par l'accueil et l'écran Statistiques). `StatistiquesScreen` : sélecteur de
période (`SegmentedButton`, état local), puis des cartes ; le stock faible lit `produitsResumesProvider` et les factures
impayées ouvrent la liste des factures. `FranchiseTvaCarte` (barres, pourcentage, étiquettes, message) sert à l'accueil et
aux statistiques. Les chiffres clés portent des `Key` (`stat-ca`, `stat-marge`…) pour les tests.

## Sauvegarde et export (étape 11)

### L'archive (`ServiceSauvegarde`, `FormatSauvegarde`)

Un `.zip` avec `donnees.json`, `fichiers.json` (format 2) et les fichiers. `donnees.json` contient un **manifeste**
(`application`, `format` = version de l'organisation du fichier (2), `versionSchema` = `AppDatabase.versionSchema`,
`versionApplication`, `creeLe`, `nombreFichiers`, `lignes` par table, et depuis le format 2 `complete` et `fichiersAbsents`)
puis `tables` : pour chacune des 20 tables, ses lignes lues par `SELECT * … ORDER BY id`, **telles que
SQLite les stocke** (dates en secondes, booléens 0/1, énumérations en texte). Rien n'est recalculé : une sauvegarde restaurée
redonne exactement les mêmes lignes (un test le vérifie table par table). Les 20 lectures se font dans **une transaction** :
l'instantané est cohérent même si l'application écrit en même temps. Les fichiers sont rangés sous
`fichiers/<dossier>/<nom>` (`photos_produits`, `factures`, `devis`, `notes_pieces_jointes`) ; la base ne garde que des noms relatifs, ils retrouvent
donc leur place.

`fichiers.json` donne, pour chaque fichier de l'archive, `{chemin: "dossier/nom", octets, sha256}`. Les fichiers sont ajoutés
à l'archive **sans compression** (`ZipFileEncoder.store` : photos et PDF sont déjà compressés), `donnees.json` et `fichiers.json`
sont compressés. Le format 1 (archive fabriquée en mémoire, sans `fichiers.json`) se lit toujours : voir « Restaurer ».

`FormatSauvegarde.tables` donne les tables **dans l'ordre où on peut les remplir** (une table après celles qu'elle
référence) ; on les vide dans l'ordre inverse. Un test compare cette liste à `allTables` de la base **et** vérifie l'ordre avec
`PRAGMA foreign_key_list` : une nouvelle table oubliée ou mal placée fait échouer la CI.

`FormatSauvegarde.colonnesFichiers` liste les colonnes de la base qui contiennent un **nom de fichier** (`produits.photo_principale_chemin`,
`photos_produit.chemin`, `cours.photo_chemin`, `depenses.photo_ticket_chemin`, `parametres_entreprise.logo_chemin`, et
`factures.pdf_chemin` marquée **remplaçable** : un PDF se refabrique). Un test vérifie que ces colonnes existent **et** qu'aucune
colonne dont le nom contient « chemin » n'a été oubliée : une future pièce jointe (étape 4) devra y être ajoutée, sinon la sauvegarde
ne pourrait pas dire qu'un fichier manque. Une sauvegarde est **incomplète** quand une photo (fichier irremplaçable) citée par les
données n'est pas dans l'archive ; les fichiers qui ne suivent pas le modèle de nom accepté à la restauration, ou qui ne se lisent
pas, ne sont pas archivés (et comptent comme manquants s'ils sont cités).

### Où et quand

Les sauvegardes sont dans `<documents>/sauvegardes/`, nommées `crochet-creations-<type>-AAAA-MM-JJ-HHMMSS.zip`
(`auto`, `manuelle`, `avant-restauration`, suffixe `-2`, `-3`… si deux tombent dans la même seconde, et `-incomplete` juste avant
`.zip` pour une sauvegarde incomplète). La date et le caractère complet viennent du nom, sans changement de schéma (la liste ne
lit donc aucune archive) ; les fichiers qui ne suivent pas ce modèle (provisoires `.tmp`, fichiers étrangers) sont ignorés.
Les écritures passent par un fichier provisoire (`….zip.tmp`) renommé ensuite : jamais d'archive à moitié écrite ; un provisoire
laissé par une interruption est effacé à la sauvegarde suivante. L'export JSON utilise `ecrireAtomiquement`.
`main()` lance `sauvegarderAutomatiquementSiBesoin()` **après** `runApp`, sans l'attendre : une sauvegarde automatique est
faite si la dernière (automatique ou manuelle, pas une copie de sécurité) date d'un jour ou plus. Rotation : 7 automatiques, 3
copies de sécurité ; les manuelles ne sont supprimées que par la personne.

### Créer une sauvegarde (`creer`)

Une seule sauvegarde ou restauration à la fois (`_enSerie` : file d'attente interne) : sinon l'une effacerait les fichiers
provisoires de l'autre (la sauvegarde automatique du démarrage peut tomber pendant un appui sur « Sauvegarder maintenant »).

1. **Lire la base** : les 20 tables dans une transaction.
2. **Lister les fichiers** présents (`photos_produits`, `factures`, `devis`, `notes_pieces_jointes`) et calculer pour chacun sa **taille et son SHA-256 en
   flux** (`sha256.bind(fichier.openRead())`, jamais le fichier entier en mémoire). Un fichier illisible n'est pas archivé. Les
   photos citées par les données mais absentes de cette liste donnent `fichiersAbsents` : la sauvegarde est **incomplète**.
3. **Contrôler la place** : `ControleEspaceLibre.octetsLibres` (somme des fichiers + JSON + marge de 10 Mo). Mesure inconnue (`null`) :
   on tente quand même. Trop peu de place : `DonneeInvalide` qui dit combien il faut et combien il reste, avant d'avoir écrit.
4. **Écrire** `….zip.tmp` avec `ZipFileEncoder` : `donnees.json`, `fichiers.json`, puis chaque fichier lu en flux.
5. **Relire** l'archive écrite (`ZipDecoder.decodeStream` sur un `InputFileStream` : seul l'annuaire central est lu) : elle doit
   contenir `donnees.json`, `fichiers.json` et **exactement** les fichiers annoncés, avec les bonnes tailles (un fichier qui a changé
   pendant la copie est détecté ici).
6. Renommer le provisoire (avec `-incomplete` si besoin), puis purger les plus anciennes sauvegardes du même type.

À la moindre erreur, le provisoire est effacé. Un refus du système d'écrire faute de place (`FileSystemException`, code ENOSPC) est
traduit en message clair. La progression est annoncée à chaque pas par un rappel `SurProgression` (`ProgressionSauvegarde` :
étape, fait, total) ; l'écran n'en redessine que toutes les 100 ms.

### Restaurer

1. `examiner(File)` (sans effet) : ouvre le zip **en flux** (`InputFileStream` : seul l'annuaire central et `donnees.json` /
   `fichiers.json` sont lus), vérifie le manifeste (`application`, `format` et `versionSchema` pas plus récents que ceux de
   l'application), le type des valeurs et les noms de fichiers (**uniquement** `fichiers/<dossier connu>/<nom>`, sans `..`, `\`
   ni `:`). Pour le **format 2**, la liste `fichiers.json` doit être bien formée et **correspondre exactement** au contenu de
   l'archive (aucun fichier absent, aucun fichier non annoncé, mêmes tailles). Les photos citées mais absentes de l'archive sont
   calculées **à partir des données et du contenu** (pas du manifeste) : vrai aussi pour une archive du format 1. Une archive
   refusée n'a produit aucune copie de sécurité ni aucun fichier.
2. **Contrôle de la place** pour les fichiers à extraire.
3. Les fichiers de l'archive sont **extraits un par un** (`ArchiveFile.writeContent` vers un `OutputFileStream`) dans des dossiers
   provisoires `….restauration`, et **relus** : taille et SHA-256 doivent être ceux annoncés (format 1 : seulement la taille).
   Un fichier abîmé arrête tout : dossiers provisoires supprimés, rien n'a été modifié, pas de copie de sécurité.
4. Copie de sécurité (`avant-restauration`) de l'état actuel. Elle vient **après** l'extraction : si on restaure justement la plus
   ancienne copie de sécurité, la nouvelle copie peut la supprimer (rotation) sans gêner la restauration en cours (un test le vérifie).
5. **Une transaction** vide les tables (ordre inverse) puis les remplit (ordre direct) avec des `INSERT` paramétrés ; chaque
   colonne de l'archive est vérifiée contre `PRAGMA table_info`. Les contraintes `CHECK` et les clés étrangères de la base
   jouent leur rôle : une archive incohérente fait échouer la transaction, qui est annulée (`DonneeInvalide`, dossiers
   provisoires supprimés, fichiers intacts).
6. `markTablesUpdated` prévient Drift (les écrans qui lisent en direct se rafraîchissent), puis chaque dossier de fichiers est
   échangé avec son dossier provisoire (renommages).
L'écran relit ensuite le mode jour / nuit restauré, remet à zéro la vente en cours et renvoie à l'accueil.

### Export CSV (`ExportCsv`, `domain/csv.dart`)

`fabriquerTextes()` lit les tables dans une transaction et produit un texte par fichier (`produits.csv`, `clients.csv`,
`ventes.csv`, `factures.csv`, `devis.csv`, `cours.csv`, `inscriptions.csv`, `depenses.csv`) ; `fabriquerArchive()` les range
dans un `.zip` (UTF-8 avec BOM). Les libellés viennent des énumérations, les noms de client sont résolus (« Client de
passage » sans fiche), les montants passent par `montantCsv` (`12,50`). `construireCsv` vérifie (assertion) que chaque ligne a
autant de cellules que d'en-têtes ; `echapperCsv` protège les cellules qui contiennent `;`, `"` ou un retour à la ligne.

### Écran et services

`SauvegardeScreen` n'a pas de logique propre : il appelle `ServiceSauvegarde`, `ExportCsv`, `ServicePartageFichiers` (partage
d'un fichier par `share_plus`) et `SelecteurFichierSauvegarde` (`file_picker`), tous fournis par des providers que les tests
remplacent (faux partage, faux sélecteur, dossiers temporaires). Une opération en cours désactive les boutons et affiche la
**progression** (`CarteProgressionSauvegarde` : « Étape n sur N : … », « x sur y fichiers » ; barre en haut de l'écran) ; une erreur
métier s'affiche telle quelle, sinon une phrase générale. Le sélecteur de fichiers donne une **copie de travail** (recopiée en flux
dans le dossier temporaire : le sélecteur 13 ne donne plus de chemin) que l'écran supprime après la restauration.

## Dossier `android/`

Le dossier `android/` n'est pas versionné. `tool/setup_android.sh` le crée avec `flutter create`,
règle le nom affiché (« Un p’tit crochet dans les stocks ») et génère les icônes. La CI exécute ce script à chaque fois.

Conséquence à garder en tête pour les étapes suivantes : toute modification de configuration Android
devra être ajoutée à ce script. `image_picker` (étape 3) n'en demande aucune : la galerie passe par le sélecteur
de photos du système, sans permission. L'appareil photo, lui, ouvre l'application photo du téléphone ; si
Android ferme l'application pendant la prise de vue, la photo est retrouvée au démarrage suivant (voir *Photos*).
Si cette contrainte gêne, on pourra versionner `android/` à la place (il suffit de retirer `/android/` du `.gitignore`).

### Signature de l'APK

`flutter create` signe la version *release* avec la clé de débogage de la machine : sur GitHub Actions, elle est recréée à
chaque exécution, donc deux APK n'ont jamais la même signature (vérifié en lisant le bloc de signature v2/v3 de plusieurs
APK de la CI), et Android refuse l'installation « par-dessus ». `tool/patch_signature_android.py` (appelé par
`setup_android.sh`) insère dans `android/app/build.gradle.kts` un `signingConfigs.create("publication")` qui lit
`ANDROID_KEYSTORE_FILE`, `ANDROID_KEYSTORE_PASSWORD` et `ANDROID_KEY_ALIAS` dans l'environnement ; la version *release* utilise cette
configuration si `ANDROID_KEYSTORE_FILE` est défini, sinon la clé de débogage. Il est idempotent et échoue bruyamment si le
modèle Gradle de Flutter change (mieux vaut une construction rouge qu'un APK signé avec la mauvaise clé).

Dans le workflow : l'étape « Préparer la clé de signature » décode le secret `ANDROID_KEYSTORE_BASE64` dans `$RUNNER_TEMP`,
contrôle qu'il s'ouvre avec le mot de passe (`keytool -list`) puis exporte les trois variables ; « Vérifier la signature de
l'APK » appelle `tool/empreinte_signature_apk.py`, qui lit le certificat dans l'APK (sans SDK Android) et le compare à
`tool/signature_attendue.txt`. La clé (`.p12`) n'est jamais dans le dépôt. L'empreinte SHA-1 sert à déclarer l'application
dans Google Cloud pour la connexion à Google Drive (étapes suivantes). Les deux scripts ont leurs tests dans `tool/tests/`
(`python3 -m unittest discover -s tool/tests -v`), lancés par la CI avant la préparation de la clé.

## Choix techniques

| Sujet | Décision | État |
|-------|----------|------|
| Base de données | **Drift** (SQLite) : requêtes typées et vérifiées à la compilation, migrations versionnées, flux de données réactifs, base en mémoire pour les tests. Meilleur choix de maintenabilité parmi les deux options du cahier des charges | mis en œuvre à l'étape 2, à confirmer |
| Dépendances | `drift`, `drift_flutter` (ouverture du fichier), `path_provider` ; en développement `drift_dev` et `build_runner`. SQLite est embarqué automatiquement par le paquet `sqlite3` | étape 2 |
| Version minimale | Dart 3.10 / Flutter 3.38 (exigé par Drift 2.35) : utiliser le canal *stable* | étape 2 |
| Modèles | Classes de lignes générées par Drift, pas de seconde série d'entités | étape 2 |
| Mémorisation du mode jour/nuit | Dans la base (`parametres_entreprise`), sans bibliothèque supplémentaire | fait |
| Photos des produits | `image_picker` (galerie et appareil photo, aucune permission à déclarer), copie dans le dossier privé de l'application ; chemin relatif en base | étape 3 |
| Variantes dans l'étape 3 | L'interface des variantes (couleur / taille, stock propre) fait partie de l'étape 3 : c'est la réalisation du champ « couleur / variante » de la fiche produit | étape 3, à confirmer |
| Factures PDF | `pdf` (mise en page), `printing` (aperçu et impression), `share_plus` (partage) ; PDF rangés dans le dossier privé, nom du fichier en base | étape 6 |
| Sauvegarde et export | `archive` (fabriquer et lire les `.zip` ; depuis l'étape 3 du plan d'évolution, **en flux** : `ZipFileEncoder`, `InputFileStream`, `OutputFileStream`) et `file_picker` (choisir un fichier à restaurer, sélecteur du système sans permission) ; partage par `share_plus` | étape 11 |
| Sauvegarde fiable | `crypto` (SHA-256 des fichiers, en flux) ; `disk_space_plus` (place libre du téléphone, derrière l'interface `ControleEspaceLibre` : une mesure impossible est traitée comme « inconnue » et ne bloque jamais une sauvegarde) | étape 3 du plan d'évolution |
| Dépendances des étapes suivantes | arriveront avec les étapes qui s'en servent | à venir |

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

- `test/core/` : montants (affichage et saisie), dates, durées, recherche sans accents, validateurs de formulaire,
  thèmes (couleurs de la charte et contrastes), mode d'affichage et sa mémorisation.
- `test/domain/` : total d'une vente (remise, frais de port, arrondis), panier (ajout, stock, quantités, remise,
  paiement saisi), statut de paiement, règles de stock,
  format des numéros, noms des listes de choix, règles de saisie d'un client. Aucun accès à la base ni à l'interface.
- `test/data/` : sur une vraie base SQLite **en mémoire** (mêmes tables, index et contraintes que sur le téléphone) :
  structure et contraintes (`schema_test.dart`), numérotation continue et sans doublon, décrémentation du stock
  « tout ou rien », archivage, variantes, réglages ; catalogue produits (résumés, fiche, duplication, inventaire,
  historique, noms de variantes uniques, flux en direct, flux simultanés qui ne se confondent pas) ; clients (règles de saisie refusées avec le bon message,
  historique complet et limité au bon client, flux en direct) ; ventes (validation avec stock, remise, frais de port,
  paiement, tout-ou-rien en cas d'échec, encaissement du solde, annulation avec remboursement et remise en stock).
- Catégories de produits : `domain/categories_produit_test` (clés d'origine, règles du nom), `categorie_repository_test` (créer,
  renommer, supprimer avec déplacement, refus sans rien changer, flux en direct), `schema_test` et `migration_schema_test`
  (version 3, migrations 1→3 et 2→3, catégories d'origine non recréées), `service_sauvegarde_test` (ancienne archive sans catégories,
  aller-retour des catégories), `produit_repository_test` (catégorie inconnue refusée), `categories_ecrans_test` (écran
  Catégories, filtre) et « + Nouvelle catégorie » dans `produit_form_test`.
- Lieux de vente : `domain/lieux_vente_test` (lieux de départ, règles du nom), `lieu_vente_repository_test` (créer, renommer, supprimer avec
  déplacement vers un lieu ou « Non renseigné », ventes annulées comptées, refus sans rien changer, flux en direct),
  `vente_repository_test` (lieu à la validation, `changerLieu` sans autre effet), `schema_test` et `migration_schema_test` (version 4,
  migration 3 → 4, anciennes ventes « Non renseigné », lieux de départ non recréés), `service_sauvegarde_test` (ancienne archive sans lieux,
  aller-retour), `export_csv_test` (colonne « Lieu de vente ») et `lieux_ecrans_test` (écran Lieux de vente, choix dans le panier, création depuis
  la feuille, lieu supprimé pendant la vente, correction dans le détail d'une vente).
- Bloc-notes : `domain/notes_test` (catégories de départ, règles du nom, du titre et du texte), `categorie_note_repository_test` (créer,
  renommer, supprimer avec déplacement vers une catégorie ou « Sans catégorie », refus sans rien changer, dates des notes inchangées,
  flux en direct), `note_repository_test` (créer, modifier, supprimer, ordre, date de modification seulement si quelque chose change),
  `schema_test` et `migration_schema_test` (version 5, migration 4 → 5, anciennes bases sans notes, catégories de départ non recréées),
  `service_sauvegarde_test` (aller-retour des catégories et des notes, archive d'avant le bloc-notes) et `notes_ecrans_test` (liste,
  filtres, nouvelle note, modification, suppression, écran Catégories de notes, déplacement des notes à la suppression d'une catégorie).
- Pièces jointes des notes (étape 4 du plan d'évolution) : `pieces_jointes_notes_test` (limites par type, nom et extension, copie en flux,
  refus avant et pendant la copie, fichier provisoire effacé, 20 pièces au plus, création / modification / suppression avec leurs
  fichiers, flux en direct du décompte), `schema_test` et `migration_schema_test` (table, contraintes, cascade, version 6, migration 5 → 6),
  `service_sauvegarde_test` (4e dossier, empreintes, restauration sur un autre téléphone, pièce absente = incomplète, `.tmp` ignoré,
  archive du schéma 5) et `notes_ecrans_test` (limites affichées, ajout, refus, retrait, abandon, ouverture, nombre dans la liste).
- Suppression d'un client ou d'un produit : `suppression_repository_test` (historique conservé, noms copiés, lignes détachées,
  inscriptions refusées), `migration_schema_test` (base du schéma 1 mise à jour sans perte), `service_sauvegarde_test`
  (archive du schéma 1), `export_csv_test` et `devis_repository_test` (client supprimé), `domain/usage_historique_test`.
- `test/widget_test.dart` et `test/presentation/` : parcours splash → accueil → réglages, écran d'erreur de
  démarrage ; liste de produits (recherche, filtres, alertes), fiche, formulaire (validations, abandon, photos),
  gestion des photos du formulaire ; liste de clients (recherche, filtres, archivés), fiche (coordonnées, historique,
  « Voir tout », archivage), formulaire (champs selon le type, validations, modification, abandon).
  Ventes : onglet Vente (client, produits, variantes, ligne libre), panier (quantités, stock, remise, frais de port),
  validation payée / acompte / plus tard, refus sans rien enregistrer, encaissement du solde, annulation,
  réouverture d'une vente depuis l'historique d'un client.
  `aide_widget.dart` fournit l'environnement commun : base en mémoire, dossier temporaire, faux sélecteur de photo,
  création de clients et de ventes.

Devis (étape 7) : `regles_devis_test` (validité, expiration, transitions de statut), `devis_repository_test` (création et
numéro, modification, statuts, expiration enregistrée, **conversion devis → facture** avec et sans acompte, profil
incomplet, PDF), `devis_pdf_test` (une page pour un devis complet, plusieurs pour un long) et `devis_ecrans_test` (liste,
création, modification, statuts, devis expiré, conversion avec et sans acompte reçu, avec facture, profil incomplet).

Cours (étape 8) : `regles_cours_test` (places, liste d'attente, refus), `panier_test` (lignes de cours),
`cours_repository_test` (création, modification, inscription avec paiement, prix convenu, cours gratuit, cours complet,
doublons, tout-ou-rien, confirmation, annulation avec et sans remboursement, réinscription, archivage, liste et fiche
en direct) et `cours_ecrans_test` (liste et filtres, formulaire, fiche, inscription payée / acompte / plus tard / gratuite,
liste d'attente, confirmation, annulation avec ou sans remboursement, cours annulé, archivage).

Dépenses (étape 9) : `regles_depenses_test` (montant, date non future, mois), `depense_repository_test` (création et
nettoyage, catégories, refus sans rien enregistrer, produit lié et inconnu, aucun effet sur le produit, modification,
liste par mois et total, filtre de catégorie, archivage et restauration, flux en direct) et `depenses_ecrans_test` (liste
et « Plus », total du mois, filtre, mois précédent, archivées, saisie, montant obligatoire, produit concerné, photo du
ticket, abandon, modification, archivage et restauration).

Statistiques (étape 10) : `statistiques_test` (arithmétique en centimes, répartition sans perte, périodes dont la semaine du
lundi, argent encaissé : acompte et solde, remboursement, remise, frais de port, cours, marge, panier moyen, meilleures
ventes, catégories, dépenses, niveaux de franchise), `statistiques_repository_test` (les quatre périodes sur une base en
mémoire, vente annulée réellement remboursée, semaine à cheval sur deux années, dépenses archivées, factures impayées,
flux en direct) et `statistiques_ecrans_test` (écran vide, changement de période, stock faible et factures impayées,
alerte de franchise en direct, tuiles de l'accueil).

Sauvegarde et export (étape 11) : `csv_test` (protection des cellules, montants), `service_sauvegarde_test` (liste des tables
= celles de la base et dans l'ordre des clés étrangères, contenu de l'archive, nommage, **aller-retour complet** sur un autre
téléphone et sur le même, copie de sécurité qui permet de revenir en arrière, archives refusées sans rien changer, restauration
annulée en cas de colonne inconnue / contrainte / liaison cassée, écrans prévenus, sauvegarde automatique et rotation, export
JSON), `export_csv_test` (contenu de chaque fichier, archive, BOM) et `sauvegarde_ecran_test` (parcours de l'écran).
`test/data/aide_donnees.dart` remplit les tables (sauf les pièces jointes, testées à part) et compare deux états de la base ligne à ligne.
Sauvegarde fiable (étape 3 du plan d'évolution) : `service_sauvegarde_test` (colonnes qui citent des fichiers, `fichiers.json` avec
tailles et SHA-256, gros fichier aller-retour, sauvegarde complète / incomplète — nom, liste, manifeste, restauration —, PDF absent non
bloquant, archives du format 1, progression, place libre insuffisante, provisoire effacé, sauvegardes simultanées, archive abîmée refusée
avant toute modification : empreinte, taille, fichier absent, non annoncé, liste mal formée, restauration de la plus ancienne copie de
sécurité) et `sauvegarde_ecran_test` (sauvegarde incomplète annoncée, avertissement avant et compte rendu après restauration, carte
de progression, copie de travail du sélecteur supprimée). L'interface `ControleEspaceLibre` est remplacée par un faux dans les tests
(la vraie mesure dépend d'Android).

Finitions (étape 12) : `photo_retrouvee_test` (la photo retrouvée est proposée par les formulaires des produits, des cours et
des dépenses, utilisée une seule fois, oubliée quand une autre photo est choisie, ignorée si son fichier a disparu).

Commandes : `dart run build_runner build --delete-conflicting-outputs`, puis `flutter analyze` et `flutter test`.
