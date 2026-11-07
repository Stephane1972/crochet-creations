# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.15.0] — Lieux de vente (en attente de validation)

### Ajouté
- **Un lieu sur chaque vente** : marché, salon, boutique, vente en ligne, ou un lieu à soi. Quatre lieux sont créés au départ
  (**Marché, Salon, Boutique, Vente en ligne**) ; ils se renomment et se suppriment comme les autres.
- **Dans le panier**, une carte « Lieu de vente » : un appui ouvre la liste des lieux, avec « Non renseigné » et **+ Nouveau lieu de
  vente** (le lieu créé est choisi tout de suite). On peut valider sans rien choisir : la vente est alors « Non renseigné ».
  Un lieu supprimé pendant que le panier est ouvert ne bloque pas la vente : elle passe en « Non renseigné ».
- **Dans le détail d'une vente**, la même carte permet de **préciser ou corriger le lieu après coup**, y compris sur une vente annulée.
  Seul le lieu change : ni les montants, ni le stock, ni les paiements, ni la facture.
- **Réglages › Lieux de vente** : la liste avec le nombre de ventes de chaque lieu, **Nouveau lieu**, **Renommer** (le nom change
  partout, les ventes restent dans le lieu) et **Supprimer**. Un lieu qui a des ventes (annulées comprises) ne se supprime qu'en
  choisissant **où les déplacer** : un autre lieu, ou « Non renseigné » ; rien n'est présélectionné. **Aucune vente n'est jamais supprimée.**
- Règles du nom : obligatoire, 60 caractères au plus, pas deux lieux de même nom (sans tenir compte des majuscules, des accents
  ni des espaces), et pas « Non renseigné » (c'est le libellé d'une vente sans lieu).
- **Export CSV** des ventes : nouvelle colonne « Lieu de vente ».

### Modifié
- Le schéma de la base passe en **version 4** : table `lieux_vente` et colonne `ventes.lieu_id`. La mise à jour est automatique ;
  **toutes les ventes déjà enregistrées restent « Non renseigné »** (aucune n'est rattachée à un lieu d'office).
- **Sauvegarde** : elle contient désormais 17 tables (`lieux_vente` avant `ventes`). Une sauvegarde faite avant cette version se
  restaure normalement : les ventes restent « Non renseigné » et les quatre lieux de départ sont créés.
- La boîte « nom » (création et renommage) est maintenant commune aux catégories de produits et aux lieux de vente ; les
  catégories fonctionnent exactement comme avant.

### Inchangé volontairement
- Le lieu appartient à la **vente**, pas à la facture ni au devis : une vente facturée n'est comptée qu'une fois.
- Les **statistiques** ne changent pas : le classement par lieu viendra avec l'étape « Statistiques » (argent encaissé, par mois,
  année, lieu et catégorie).
- Le « lieu » d'un **cours** (l'endroit où il se donne) est une autre notion : il n'est pas touché.

### Vérifié
- Tests de données (`lieu_vente_repository_test`, `vente_repository_test`, `schema_test`, `migration_schema_test`,
  `service_sauvegarde_test`, `export_csv_test`, `domain/lieux_vente_test`) et d'écrans (`lieux_ecrans_test` : Réglages, panier,
  création depuis la feuille, lieu supprimé pendant la vente, correction dans le détail d'une vente).

## [0.14.3] — Signature stable de l'APK

### Ajouté
- **L'APK est maintenant signé avec une clé stable** : une fois la clé installée dans les « secrets » du dépôt GitHub
  (deux secrets, voir README, *Signature de l'application*), chaque APK construit par la CI porte la même signature et
  **s'installe par-dessus la version précédente, sans désinstaller ni perdre les données**. Jusqu'ici chaque construction
  était signée avec une clé de débogage recréée à chaque fois : Android refusait donc l'installation « par-dessus ».
- `tool/patch_signature_android.py` : adapte `android/app/build.gradle.kts` (généré par `flutter create`) pour signer la
  version *release* avec la clé stable quand elle est fournie, sinon avec la clé de débogage ; il s'arrête avec une erreur
  claire si le modèle de Flutter change. Appelé par `tool/setup_android.sh`.
- `tool/empreinte_signature_apk.py` : lit la signature d'un APK (sans SDK Android) et affiche les empreintes SHA-256 et SHA-1
  du certificat ; compare au besoin à l'empreinte attendue, `tool/signature_attendue.txt` (information publique).
- Workflow : étape « Préparer la clé de signature » (lit les secrets, contrôle la clé et le mot de passe, échoue clairement
  si l'un est faux), étape « Vérifier la signature de l'APK » (construction en échec si l'empreinte n'est pas celle attendue),
  empreintes affichées dans le résumé de l'exécution et dans les notes de la pré-version. La lecture des secrets est tolérante
  aux collages faits depuis un téléphone (titres ou consignes collés autour de la clé : la plus longue ligne de base64 est retenue,
  avec un avertissement ; espaces et retours à la ligne autour du mot de passe ignorés) ; une clé tronquée ou un mauvais mot de passe
  échouent avec un message chiffré (longueurs) qui ne révèle rien de la clé.

### Vérifié en CI
- Deux constructions successives du même code (APK différents octet pour octet) portent **le même certificat** :
  SHA-256 `44:7A:F7:AB:…:2F:D3:84`, SHA-1 `9A:AF:31:A6:51:CD:BB:E1:3E:DE:A3:C9:1C:52:E0:D9:D9:E9:69:D2` ; les constructions sans les
  secrets, elles, changeaient de certificat à chaque fois.
- `tool/tests/test_signature.py` (11 tests, lancés par la CI, sans Flutter ni SDK Android) : branchement de la clé sur une copie du
  modèle Gradle de Flutter 3.47.9 (idempotence, échec bruyant si le modèle change), lecture du certificat dans un faux APK signé
  (schémas v2 et v3), empreinte conforme / différente / fichier illisible.
- `.gitignore` : les clés `*.p12` et `*.pfx` ne peuvent plus être versionnées par erreur.

### Inchangé volontairement
- Sans les secrets (copie du dépôt, pull request d'un tiers) la CI fonctionne comme avant, avec la clé de débogage et un avertissement.
- Aucun changement dans l'application elle-même : base, écrans, PDF et sauvegardes sont identiques à la 0.14.2.

### À savoir une seule fois
- Le premier APK signé avec la clé stable n'a pas la même signature que l'application déjà installée : Android refusera de
  l'installer par-dessus. Procédure : faire une sauvegarde (*Réglages › Sauvegarde et export*) et la partager **hors du
  téléphone**, désinstaller, installer le nouvel APK, restaurer la sauvegarde. Ensuite, toutes les mises à jour se feront par-dessus.
- Cette signature fixe est aussi un préalable à la connexion à Google Drive (étapes suivantes).

## [0.14.2] — Logo de l'entreprise sur les factures et les devis (en attente de validation)

### Modifié
- Les **factures et les devis** portent maintenant le **logo de l'entreprise** (« Un p’tit crochet par ici », image fournie) en haut à
  gauche, à la place de l'ancien logo monochrome. Il est imprimé en couleurs, plus grand qu'avant (96 × 90 pt) pour rester lisible ;
  le nom de l'entreprise, lui, reste celui saisi dans *Mon entreprise* et s'imprime à côté du logo. Fichier : `assets/images/logo_entreprise.jpg`
  (l'image fournie, recadrée, 640 px de large, JPEG de 63 Ko : un PDF reste léger).

### Supprimé
- `assets/images/logo_mono.png` et `logo_mono.svg` (ancien logo monochrome des PDF), devenus inutiles.

## [0.14.1] — Nouveau nom et nouveau logo

### Modifié
- **Nom de l'application : « Un p’tit crochet dans les stocks »** (au lieu de « Crochet & Créations »), à chaque endroit où
  le nom de l'application est affiché : nom sous l'icône Android (`tool/setup_android.sh`), écran de démarrage, réglages,
  titre de l'application, sujets des partages de sauvegardes et d'exports, texte d'aide de *Mon entreprise*, métadonnées des
  PDF (`creator`), description du paquet. Le message d'une archive refusée dit simplement « l'application ».
- **Logo** : la fillette aux pelotes (image fournie) devient l'**icône de lancement Android** (icône adaptative, fond `#FCE5E6`,
  logo entier réduit à 62 % pour rester visible avec tous les masques d'Android ; icône classique = le logo lui-même) et le
  **logo dans l'application** (`AppLogo` : écran de démarrage, accueil, réglages), en carré aux coins arrondis.
- `tool/generate_icons.py` part maintenant du logo fourni (`assets/icon/logo_source.png`, version haute définition de
  1254 × 1254 px) et produit le premier plan de l'icône et `assets/images/logo_application.png`.
- La branche a été mise à jour avec `main` (suppression des clients et produits, catégories modifiables) : la version passe
  à 0.14.1.
- Documentation : l'étape 12 est marquée comme validée.

### Supprimé
- L'ancien logo vectoriel en couleur (`logo.svg`), les anciennes icônes (`app_icon.png`, `app_icon_monochrome.png`) et la
  dépendance `flutter_svg`, qui ne servaient plus qu'à l'afficher.

### Inchangé volontairement
- Identifiants techniques : nom du paquet `crochet_creations`, identifiant Android `fr.crochetcreations.crochet_creations`,
  dépôt GitHub, préfixe `crochet-creations-` des fichiers de sauvegarde et d'export, identifiant `crochet-creations` du
  manifeste des sauvegardes. Les changer casserait la mise à jour de l'application installée et la restauration des
  anciennes sauvegardes.
- Les **factures et devis** gardent l'ancien logo monochrome (`logo_mono.png`) et le nom saisi dans *Mon entreprise* : un autre
  logo, celui de l'entreprise, doit être fourni.

### Limites connues et hypothèses (à confirmer)
- Le nom est long : sous l'icône, Android l'affiche sur deux lignes et le **coupe** probablement (« Un p’tit crochet… »).
- Le logo contient du texte (« Un p'tit crochet par ici ») : à la taille d'une icône, ce texte est trop petit pour être lu. Une
  variante recadrée sur la fillette (sans texte) donnerait une icône plus lisible.
- Plus de version monochrome pour les icônes thématiques d'Android 13 : l'icône reste en couleurs.

## [0.14.0] — Catégories de produits modifiables (validée)

Seconde demande de Stéphane après l'étape 12 : ajouter une catégorie à la main depuis « Nouveau produit », ou en supprimer une.

### Ajouté
- **Créer une catégorie depuis le formulaire produit** : la liste « Catégorie » se termine par **« + Nouvelle catégorie »** ; une
  petite boîte demande le nom, crée la catégorie tout de suite et la sélectionne. Un nom vide, trop long (60 caractères) ou déjà
  pris (sans tenir compte des majuscules, des accents ni des espaces) est expliqué dans la boîte, qui reste ouverte.
- **Écran « Catégories »** (*Plus → Réglages → Catégories*) : la liste avec le nombre de produits de chacune (archivés compris),
  **Nouvelle catégorie**, **Renommer** et **Supprimer**. Les cinq catégories d'origine (Crochet, Doudou, Boucles d'oreilles,
  Accessoire, Sur mesure) sont des catégories comme les autres : on peut les renommer ou les supprimer.
- **Supprimer une catégorie qui contient des produits** : l'application demande **où les déplacer** (aucune destination n'est
  présélectionnée), déplace tous les produits, archivés compris, puis supprime la catégorie, en une seule opération « tout ou
  rien ». Une catégorie vide se supprime après une simple confirmation. Si c'est la seule catégorie et qu'elle contient des
  produits, l'application demande d'en créer une autre d'abord.
- `CategorieRepository` (lister, observer, créer, renommer, supprimer avec déplacement), `domain/categories_produit.dart`
  (clés et noms de départ, règles du nom), `presentation/produits/categories_screen.dart`, `categorie_dialogues.dart`,
  `categories_providers.dart`.
- Tests : `categorie_repository_test`, `domain/categories_produit_test`, `categories_ecrans_test` (ajout, renommage, suppression
  avec déplacement, filtre de la liste des produits), « + Nouvelle catégorie » dans `produit_form_test`, migrations 1→3 et 2→3
  (`migration_schema_test`), sauvegarde et restauration des catégories (`service_sauvegarde_test`).

### Modifié
- **Schéma de la base : version 3** (migration automatique au premier lancement) : nouvelle table `categories_produit` (`id`, `cle`,
  `nom`, `position`) remplie avec les cinq catégories d'origine. `produits.categorie` garde le même texte : c'est la **clé** de la
  catégorie (`crochet`, `doudou`, `bouclesOreilles`, `accessoire`, `surMesure`, comme avant), donc **aucun produit n'est modifié**
  par la migration. Une catégorie créée reçoit une clé interne `cat_…` qui ne change jamais ; **renommer ne touche à aucun produit**.
- Le type `CategorieProduit` (liste de choix fixe) disparaît de `enums.dart` ; le dépôt de produits refuse une catégorie qui n'existe
  pas. La liste des produits, ses filtres, la fiche, les statistiques (« catégories les plus rentables », classées à marge égale
  dans l'ordre de la liste) et l'export CSV utilisent le **nom actuel** des catégories. Un filtre sur une catégorie supprimée est
  retiré tout seul.
- **Sauvegarde** : la sauvegarde contient désormais 16 tables (`categories_produit` avant `produits`). Une sauvegarde faite avant
  cette version (schéma 1 ou 2) se restaure normalement : les cinq catégories d'origine sont alors recréées.

### Décisions prises avec Stéphane
- Catégories gérées **depuis le formulaire produit et depuis un écran « Catégories » des Réglages**.
- Supprimer une catégorie utilisée : **proposer de déplacer ses produits** dans une autre catégorie.
- Livraison en **deux pull requests** : suppression d'abord (0.13.0), catégories ensuite (cette version).

## [0.13.0] — Supprimer un client ou un produit (validée)

Demande de Stéphane après l'étape 12 : pouvoir supprimer un client et un objet à vendre. Première des deux demandes (la
seconde, les catégories de produits, fait l'objet d'une autre pull request).

### Ajouté
- **Supprimer un client** (fiche client, menu ⋮ → « Supprimer ») et **supprimer un produit** (fiche produit, menu ⋮ →
  « Supprimer »), avec confirmation. Un élément **qui n'a jamais servi** demande une confirmation simple ; un élément **qui a
  déjà servi** demande une confirmation renforcée (« Supprimer définitivement ») qui dit où il apparaît (« 2 ventes, 1 facture
  et 1 devis ») et rappelle que l'archivage existe.
- **L'historique est conservé.** Client supprimé : ses ventes et ses devis gardent son nom (nouvelle colonne `client_nom`,
  affiché « Camille Martin (client supprimé) ») ; ses factures gardent son nom, son adresse et son SIRET, déjà copiés à
  l'émission. Produit supprimé : les lignes de vente et de devis gardent leur désignation, leur quantité et leur prix, mais ne
  sont plus liées à un produit ; ses variantes et ses photos (fichiers compris) sont effacées ; les dépenses qui le désignaient
  sont conservées, sans lien. Le nom copié suit le devis converti en commande, puis la facture.
- `UsageHistorique` / `ElementUsage` (`domain/usage_historique.dart`) : « où apparaît cet élément », en phrase française ;
  `ClientRepository.usage`, `nombreInscriptions`, `ProduitRepository.usage`, `nombreDepensesLiees` ; `nomClientOuCopie`
  (`client_vues.dart`) ; boîte d'information `informer` (`dialogues.dart`).
- Tests : `suppression_repository_test` (client et produit utilisés ou non, noms copiés, lignes détachées, factures, dépenses,
  références non réutilisées, inscriptions refusées), `migration_schema_test` (base du schéma 1 mise à jour), restauration d'une
  sauvegarde du schéma 1 et d'une sauvegarde faite après suppression, export CSV, conversion d'un devis dont le client a été
  supprimé, `usage_historique_test`, boîtes de dialogue des fiches client et produit.

### Modifié
- **Schéma de la base : version 2** (migration automatique au premier lancement) : colonne `client_nom` ajoutée à `ventes` et à
  `devis`. Les anciennes sauvegardes (schéma 1) se restaurent normalement, la colonne restant vide.
- Ventes, devis, export CSV (ventes et devis) et PDF de devis affichent le nom copié quand la fiche du client n'existe plus.

### Décisions prises avec Stéphane
- Supprimer un client ou un produit **déjà utilisé** : **autorisé, historique conservé** (confirmation renforcée).
- Livraison en **deux pull requests** : suppression d'abord, catégories ensuite.

### Limites connues et hypothèses (à confirmer)
- **Un client inscrit à un cours ne peut pas être supprimé** (la liste des inscrits a besoin de sa fiche) : l'application propose
  de l'**archiver**, ou il faut le désinscrire d'abord.
- Une suppression est **définitive** : seule une sauvegarde permet de revenir en arrière. Restaurer une sauvegarde ancienne
  fait revenir le client ou le produit supprimé depuis.
- Les coordonnées et les notes d'un client supprimé disparaissent (seul son nom reste sur les ventes et les devis, plus son
  adresse sur les factures déjà émises). Un client supprimé qu'on veut refacturer doit être recréé.
- Modifier un devis dont le client a été supprimé garde son nom tant qu'on ne choisit pas un autre client ; l'écran de
  modification, lui, affiche « Aucun client ».
- Les produits d'un devis dont le produit a été supprimé restent des lignes libres : le devis se convertit en commande sans
  toucher au stock.

## [0.12.0] — Étape 12 : finitions

### Ajouté
- **Photo retrouvée après une fermeture d'Android** : `SelecteurPhoto.retrouverPhotoPerdue()` (`image_picker` :
  `retrieveLostData`) est appelée **une fois au démarrage**, dans `main()`, avant l'affichage du premier écran ; le chemin
  retrouvé est conservé en mémoire par `photoRetrouveeProvider` (`presentation/common/photo_retrouvee.dart`). La feuille de
  choix de photo propose alors **« Utiliser la photo retrouvée »** en premier choix. Elle disparaît dès qu'on l'utilise,
  qu'on choisit une autre photo, ou si le fichier n'existe plus ; refermer la feuille sans rien choisir la garde pour la
  prochaine fois. Le formulaire lui-même n'est pas restauré.
- Tests : `photo_retrouvee_test` (offerte, utilisée, consommée ; autre photo choisie ; feuille refermée ; fichier disparu ;
  sans photo retrouvée ; formulaires produit, cours et dépense). Le faux sélecteur de photo et `EnvironnementTest`
  (`photoRetrouvee`) connaissent la nouvelle option.

### Modifié
- **Feuille « choix de photo » regroupée** : le formulaire des cours n'a plus sa propre copie ; les trois formulaires
  (produit, cours, ticket de dépense) utilisent `demanderChoixPhoto` et `choisirFichierPhoto`
  (`presentation/common/choix_photo.dart`), avec les mêmes textes et le même message d'erreur.
- Le texte des réglages indique « étape 12 sur 12 ».

### Décisions prises avec Stéphane
- Périmètre de l'étape 12 : **les points déjà repérés** (feuille de photo à regrouper, photo perdue à retrouver).
- Photo perdue : **la garder et la proposer** au prochain choix de photo (le formulaire n'est pas restauré).

### Limites connues et hypothèses (à confirmer)
- `retrieveLostData` ne fonctionne que sous Android et ne peut être appelée qu'**une fois** : si l'application est
  rouverte sans qu'on choisisse de photo, la photo retrouvée reste proposée jusqu'à la fermeture de l'application, mais
  n'est plus retrouvée au démarrage suivant.
- La photo retrouvée reste dans le dossier temporaire du téléphone tant qu'elle n'est pas utilisée ; une fois choisie, elle
  est copiée dans l'application comme n'importe quelle photo.
- Le numéro de version reste en `0.x` : le passage à **1.0.0** est à décider par Stéphane à la validation.
- Le schéma de la base n'a pas changé : pas de migration. Aucune nouvelle dépendance.

## [0.11.0] — Étape 11 : sauvegarde et export

### Ajouté
- **Sauvegarde** (`data/sauvegarde/service_sauvegarde.dart`, `format_sauvegarde.dart`) : une archive `.zip` avec `donnees.json`
  (manifeste : application, version du format et du schéma, date, nombre de lignes par table ; puis les lignes des 15 tables
  **telles qu'elles sont en base**, lues d'un seul tenant dans une transaction) et les fichiers (`fichiers/photos_produits/`,
  `fichiers/factures/`, `fichiers/devis/`). Rangée dans le dossier `sauvegardes/` de l'application, nommée d'après son type et
  son heure (`crochet-creations-manuelle-2026-10-31-134912.zip`).
- **Sauvegarde automatique** à l'ouverture de l'application : si la dernière sauvegarde (automatique ou manuelle) date d'un
  jour ou plus ; **7 automatiques** conservées. Lancée en arrière-plan après l'affichage du premier écran ; un échec est
  seulement noté dans le journal, il ne gêne jamais l'utilisation.
- **Restauration** : vérification de l'archive sans rien toucher (c'est bien une sauvegarde de cette application, format et
  schéma pas plus récents, aucun fichier rangé hors des dossiers prévus), **copie de sécurité** de l'état actuel (3
  conservées), fichiers préparés dans un dossier provisoire, remplacement de la base en **une seule transaction** (tout ou
  rien : tables vidées des dernières aux premières, remplies des premières aux dernières, colonnes vérifiées, contraintes
  et clés étrangères de la base appliquées), puis échange des dossiers de fichiers. Les écrans ouverts sont prévenus.
- **Export CSV** (`data/sauvegarde/export_csv.dart`, `domain/csv.dart`) : un `.zip` avec `produits`, `clients`, `ventes`,
  `factures`, `devis`, `cours`, `inscriptions` et `depenses` ; point-virgule, fins de ligne `\r\n`, UTF-8 avec marque
  d'ordre des octets, montants `12,50`, dates `05/03/2026`, listes de choix en toutes lettres, éléments archivés inclus.
- **Export JSON** complet (les mêmes données que la sauvegarde, sans fichiers).
- **Écran « Sauvegarde et export »** (23) : sauvegarder maintenant, liste des sauvegardes du téléphone (partager, restaurer,
  supprimer), restaurer depuis un fichier choisi dans le téléphone, exporter en CSV ou en JSON ; confirmations, messages
  clairs et barre de progression.
- Dépendances : `archive` (fabriquer et lire les `.zip`) et `file_picker` (choisir le fichier à restaurer). Le partage passe
  par `share_plus`, déjà présent (`ServicePartageFichiers`).
- Tests : `csv_test`, `service_sauvegarde_test` (aller-retour complet sur un autre téléphone et sur le même, archives
  refusées, restauration annulée en cas d'erreur, sauvegarde automatique et rotation, export JSON), `export_csv_test` et
  `sauvegarde_ecran_test` (parcours de l'écran avec faux sélecteur de fichier et faux partage).

### Modifié
- *Réglages → Sauvegarde et export* ouvre le vrai écran ; l'écran « Bientôt disponible » n'existe plus (la liste
  `EcransAVenir.parRoute` est vide).
- Le texte des réglages indique « étape 11 sur 12 ».

### Décisions prises avec Stéphane
- Sauvegarde = **archive `.zip` complète** (données et photos).
- Sauvegarde **automatique à l'ouverture** si la dernière date de plus d'un jour ; **7 conservées**.
- Restauration qui **remplace tout**, avec **copie de sécurité préalable**.
- Export CSV en **un `.zip`, un CSV par type**.

### Limites connues et hypothèses (à confirmer)
- Les **PDF des factures et des devis** sont inclus dans la sauvegarde (on les retrouve tels qu'émis) ; pas seulement les
  données.
- **CSV** : séparateur point-virgule, UTF-8 avec marque d'ordre des octets, montants à virgule : pensé pour Excel et
  LibreOffice en français.
- La date de la « dernière sauvegarde » est lue dans le **nom du fichier** (aucun changement de schéma) : renommer un fichier
  du dossier `sauvegardes/` le fait ignorer.
- Restaurer **depuis un fichier** demande le sélecteur de fichiers d'Android (`file_picker`) ; tous les fichiers sont
  proposés, car certaines applications enregistrent un `.zip` sous un type que le filtre ne reconnaît pas.
- Les **sauvegardes manuelles** ne sont jamais supprimées automatiquement (bouton « Supprimer » dans la liste) ; les copies
  de sécurité d'avant restauration sont limitées aux 3 dernières.
- La sauvegarde est **entièrement construite en mémoire** (données + photos) : très à l'aise pour quelques centaines de
  photos réduites (1 600 px), mais une très grosse photothèque pourrait être lourde sur un vieux téléphone.
- Les sauvegardes restent **sur le téléphone** : si le téléphone est perdu ou réinitialisé, elles le sont aussi. Il faut en
  **partager** une de temps en temps (e-mail, Drive…). Pas de cloud automatique en version 1.
- Une sauvegarde faite avec une version **plus récente** de l'application est refusée ; une plus ancienne est acceptée tant
  que ses colonnes existent encore (les migrations de schéma futures devront en tenir compte).

## [0.10.0] — Étape 10 : statistiques (validée)

### Ajouté
- **Calculs des statistiques** (`domain/calculs/statistiques.dart`, sans base ni interface) : périodes (jour, semaine du lundi,
  mois, année), **argent encaissé** réparti entre les lignes d'une vente au prorata de leur valeur après remise (méthode du
  plus fort reste : aucun centime perdu, remboursements compris), objets / prestations / cours, **coût de matière** imputé de
  la même façon, marge, panier moyen, meilleures ventes (5), catégories rentables, dépenses par catégorie, niveaux d'alerte
  de la franchise de TVA (`ok`, `approche` dès 80 %, `depasse` au-delà du seuil).
- **`StatistiquesRepository`** (lecture seule) : lit ventes, lignes, paiements, dépenses actives et factures émises, calcule
  les quatre périodes en une passe, compte les **factures impayées** (nombre et reste à encaisser) et fournit un flux mis à
  jour à chaque écriture (`Statistiques`, `statistiques_vues.dart`).
- **Écran Statistiques** (20, *Plus → Statistiques*) : sélecteur de période, chiffre d'affaires (objets, cours et prestations,
  dont cours), marge estimée, panier moyen, revenus des cours, meilleures ventes, catégories les plus rentables, dépenses par
  catégorie, stock faible, factures impayées (un appui ouvre la liste des factures) et carte de franchise de TVA.
- **Carte de franchise de TVA** partagée (`FranchiseTvaCarte`) : barres par seuil (85 000 € objets, 37 500 € cours et
  prestations), pourcentage atteint, étiquettes « Seuil approché » / « Seuil dépassé » et message.
- `horlogeProvider` (heure « maintenant » remplaçable) pour des tests d'écran à date fixe.
- Tests : calculs (`statistiques_test`), dépôt sur base en mémoire (`statistiques_repository_test`) et scénarios d'écran
  (`statistiques_ecrans_test`).

### Modifié
- **Accueil** : « Ventes du mois », « Cours du mois » et « Factures impayées » affichent de vrais chiffres (les deux premières
  tuiles ouvrent les statistiques, la troisième la liste des factures) ; la carte de franchise est celle des statistiques.
- *Plus → Statistiques* ouvre le vrai écran ; l'écran « Bientôt disponible » des statistiques disparaît.
- Le texte des réglages indique « étape 10 sur 12 ».

### Décisions prises avec Stéphane
- **Chiffre d'affaires = argent encaissé** (paiements reçus, remboursements déduits), et non les ventes validées.
- **Marge estimée = marge sur coût matière** (argent encaissé − coût de la matière des articles vendus) ; les dépenses sont
  affichées séparément, par catégorie.

### Limites connues et hypothèses (à confirmer)
- On ne voit que la période **en cours** (aujourd'hui, cette semaine, ce mois-ci, cette année) : pas de navigation vers les
  périodes passées. La semaine commence le **lundi**.
- Les **frais de port** comptent avec les objets ; une **remise** est répartie au prorata des lignes de la vente.
- **Meilleures ventes** et **panier moyen** se calculent sur les ventes **validées et faites** pendant la période (pas sur
  l'argent encaissé) ; les cours n'entrent pas dans les meilleures ventes.
- Les cours et les prestations libres sont comptés **sans coût de matière** dans la marge ; les **catégories rentables** ne
  regardent que les lignes liées à un produit du catalogue.
- « Ventes du mois » de l'accueil = argent encaissé ce mois-ci **hors cours** ; « Cours du mois » = argent encaissé sur les
  cours ; « Factures impayées » = factures **émises** dont la vente n'est pas entièrement payée.
- **Franchise de TVA** : calculée sur l'argent encaissé depuis le **1er janvier**, objets d'un côté, cours et prestations de
  l'autre ; alerte « approche » à partir de **80 %** du seuil, « dépassé » **strictement** au-dessus. Les règles exactes de la
  franchise en base (ce qui entre dans chaque seuil, tolérances de dépassement) ne sont pas vérifiées par l'application :
  à confirmer avec un comptable ou l'URSSAF.
- Un écran laissé ouvert **au-delà de minuit** ne change de période qu'à la prochaine modification de données.

## [0.9.0] — Étape 9 : dépenses (validée)

### Ajouté
- **Règles des dépenses** (`domain/regles_depenses.dart`, sans base ni interface) : montant supérieur à 0, date jamais
  dans le futur (le jour même est permis), longueurs maximales (fournisseur, description), mois et bornes de mois.
- **`DepenseRepository`** : créer, modifier, **archiver / restaurer** (une dépense ne se supprime pas), lister **par mois**
  (avec le **total** des lignes affichées, filtre de catégorie, dépenses archivées à part) et suivre la liste en direct
  (`ListeDepenses`, `DepenseLigne` avec le produit concerné). Un produit inconnu est refusé ; la date est enregistrée
  à minuit, heure locale.
- **Écrans** : liste des dépenses (19) avec sélecteur de mois, total, pastilles de catégorie et icône d'archive (dépenses archivées) ;
  formulaire de création / modification (date, catégorie, montant, fournisseur, description, **photo du ticket**,
  **produit concerné**) avec abandon confirmé et menu d'archivage.
- `selecteur_produit.dart` : choix du produit (recherche par nom ou référence, « Aucun produit »).
  `common/choix_photo.dart` : la feuille « Prendre une photo / Galerie / Retirer », réutilisable (le formulaire des cours
  gardait sa propre copie ; regroupée à l'étape 12).
- `formatMois` (« octobre 2026 ») dans `core/utils/date_fr.dart`.
- Tests : règles (`regles_depenses_test`), dépôt (`depense_repository_test`), `formatMois` et scénarios d'écran
  (`depenses_ecrans_test`).

### Modifié
- *Plus → Dépenses* ouvre la vraie liste ; l'écran « Bientôt disponible » des dépenses disparaît.
- Le texte des réglages indique « étape 9 sur 12 ».

### Décisions prises avec Stéphane
- **Liste** : total du **mois** affiché en haut, avec filtres par catégorie et par mois (les totaux détaillés par
  catégorie restent pour les statistiques, étape 10).
- **Produit concerné** : **simple information**, sans effet sur le coût matière, la marge ni la fiche du produit.

### Limites connues et hypothèses
- Le **total affiché est celui des lignes visibles** : avec une catégorie choisie, c'est le total de cette catégorie.
- Les dépenses **archivées** n'entrent dans aucun total ; dans la vue des archivées (icône d'archive de la barre du haut), on voit leur nombre, pas de total ni de filtre de catégorie.
- **Une seule photo** de ticket par dépense. Elle s'affiche en entier dans le formulaire (pas de zoom plein écran).
- Pas de date dans le futur ; on ne peut pas non plus naviguer vers un mois à venir. On remonte mois par mois pour
  retrouver une dépense ancienne (pas de recherche en V1).
- Le schéma de la base n'a pas changé : pas de migration.

## [0.8.0] — Étape 8 : cours et inscriptions (validée)

### Ajouté
- **Règles des cours** (`domain/regles_cours.dart`, sans base ni interface) : fin et fin de cours, places restantes,
  statut d'une nouvelle inscription (confirmée ou liste d'attente), ordre de la liste d'attente, contrôle d'un cours
  (titre, durée, prix, places), refus d'inscription (cours annulé ou archivé), refus de confirmation (pas en attente,
  cours complet, pas la première personne), annulation d'une inscription, archivage (cours terminé ou annulé).
- **`CoursRepository`** : créer, modifier, annuler / rétablir, archiver / restaurer un cours ; **inscrire**
  (place libre : inscription confirmée **et vente** ; cours complet : liste d'attente sans vente), **confirmer** la
  première personne en attente, **annuler une inscription** (avec ou sans remboursement), lister (« À venir »,
  « Passés », « Archivés ») et consulter la fiche d'un cours en direct (`CoursResume`, `CoursDetail`,
  `InscriptionDetail` : client, vente, net encaissé, facture, rang d'attente).
- **Ligne de vente « cours »** : `Panier.ajouter(coursId: …)` (toujours une prestation, jamais un produit, non
  modifiable depuis le panier) ; `VenteRepository.valider` enregistre `lignes_vente.cours_id`.
- **Écrans** : liste des cours (16), fiche du cours (17), inscription et confirmation (18), formulaire de création /
  modification (photo, date et heure, durée, lieu, prix, places, niveau, matériel inclus). Menu de la fiche : modifier,
  annuler / rétablir le cours, archiver / restaurer.
- `SaisiePaiement` : la rubrique « Paiement » (payée, acompte, plus tard, mode) du panier est devenue un composant
  réutilisé par l'inscription à un cours.
- `formatHeure` (« 14 h 30 », « 9 h 05 ») dans `core/utils/date_fr.dart`.
- Tests : règles (`regles_cours_test`), panier (`panier_test`, lignes de cours), dépôt (`cours_repository_test`) et
  scénarios d'écran (`cours_ecrans_test`).

### Modifié
- *Plus → Cours* ouvre la vraie liste ; l'écran « Bientôt disponible » des cours disparaît. L'historique d'un client
  ouvre la fiche du cours.
- Le choix du client peut exiger une fiche (`autoriserAucun: false`) : pas de « client de passage » pour une
  inscription.
- Le texte des réglages indique « étape 8 sur 12 ».

### Décisions prises avec Stéphane
- **Une facture par inscrit**, pas de reçu à part : l'inscription crée une vente, et le bouton « Créer la facture » de
  la vente sert de facture ou de reçu.
- **Liste d'attente manuelle** : bouton « Confirmer » sur la première personne en attente, aucune promotion
  automatique.
- **Annulation d'une inscription payée** : le choix est fait **à chaque fois** entre « Annuler et rembourser » et
  « Annuler en gardant le paiement ».
- **Cours annulé** : gestion **inscrit par inscrit** (le cours passe à « Annulé », les inscriptions restent affichées,
  on les annule et rembourse une à une).

### Limites connues et hypothèses
- Le **prix d'une inscription** est celui du cours par défaut, modifiable pour une personne ; il est enregistré avec
  l'inscription (modifier le cours ne le change plus).
- **Une inscription par client et par cours** (clé unique en base). Après une annulation, la même personne peut se
  réinscrire : la ligne est réutilisée avec une nouvelle vente.
- Une personne en **liste d'attente n'a pas de vente** : le mode de paiement se choisit à la confirmation. Seule la
  première personne peut être confirmée, et seulement si une place est libre.
- Le cours est vendu comme **prestation** (une ligne « Cours : titre » avec la date, la durée et le lieu), sans effet sur
  le stock. Un cours à 0 € crée une vente à 0 € considérée comme payée.
- « **Annuler en gardant le paiement** » ne touche ni à la vente ni aux paiements : le solde éventuel reste dû, et la
  vente peut être annulée plus tard depuis son écran.
- Annuler un **cours** ne touche pas aux inscriptions. On peut inscrire des personnes à un cours **déjà passé** (cours
  rattrapé après coup) ; pas à un cours annulé ou archivé.
- Un cours **ne se supprime pas** ; seul un cours terminé ou annulé peut être archivé.
- Le nombre de places ne peut pas descendre sous celui des personnes confirmées.
- Le schéma de la base n'a pas changé : pas de migration.

## [0.7.0] — Étape 7 : devis (validée)

### Ajouté
- **Règles des devis** (`domain/regles_devis.dart`, sans base ni interface) : validité par défaut (30 jours), statut
  affiché (un devis brouillon ou envoyé dont la validité est dépassée est « expiré »), transitions de statut
  autorisées, devis modifiable / convertible, contrôle des dates et de l'acompte.
- **`DevisRepository`** : créer (numéro **DEVIS-AAAA-NNNN** attribué dans la même transaction), modifier, changer le
  statut, actualiser les expirations (enregistrées en base), **convertir** en commande ou en commande et facture,
  lister et consulter en direct, fabriquer / ranger / relire le PDF. Les lignes, la remise et les frais de port
  réutilisent le `Panier` de l'étape 5 (lignes libres).
- **Conversion** : une vente validée (sans effet sur le stock) reprend les lignes, la remise, les frais de port et le
  client du devis ; la note de la commande porte « Commande issue du devis N » et les notes du devis. Le devis passe
  à « accepté » et est relié à la vente (c'est ce lien qui le marque « converti en commande »). Avec
  **« Acompte reçu »**, le premier paiement (montant de l'acompte, mode au choix) est enregistré sur la vente. Le profil
  « Mon entreprise » est vérifié **avant** toute écriture quand une facture est demandée ; si la facture échoue après
  la commande, le message l'indique et la commande reste créée.
- **PDF du devis** (`genererDevisPdf`) : même présentation que la facture (mise en page partagée dans
  `data/pdf/elements_pdf.dart`), titre « DEVIS », « Établi le » et « Valable jusqu'au », conditions (validité, délai de
  réalisation, acompte demandé, IBAN pour le régler) à gauche des totaux, mention 293 B, cadre **« Bon pour accord »**.
  Un devis court tient sur une page, un long continue sur plusieurs.
- **Écrans** : liste des devis (13), création / modification (14), détail avec aperçu PDF, **Partager**, **Imprimer**,
  changement de statut, **Modifier** et **Convertir** (15 pour la conversion). L'aperçu n'est refait que si le contenu
  imprimé change (pas à chaque changement de statut).
- Tests : règles (`regles_devis_test`), dépôt (`devis_repository_test`, dont la **conversion devis → facture**), PDF
  (`devis_pdf_test`) et 11 scénarios d'écran (`devis_ecrans_test`).
- La CI publie aussi des exemples de PDF de devis (complet, simple, long).

### Modifié
- *Plus → Devis* ouvre la vraie liste ; les écrans « Bientôt disponible » des devis disparaissent. L'historique d'un
  client affiche le statut réel du devis et l'ouvre.
- `Panier.avecLigneModifiee` : modification d'une ligne libre (utilisée par le formulaire de devis).
- Réutilisation depuis l'étape 5 : dialogue de ligne libre, choix du client (avec libellés « Aucun client » pour un
  devis) et fenêtre « Informations manquantes » (`proposerProfilComplet`).
- `StockageFactures` devient `StockagePdf` (factures et devis, chacun dans son dossier).
- Message d'erreur de l'aperçu : « Impossible d'afficher l'aperçu de ce document. ».
- Le texte des réglages indique « étape 7 sur 12 ».

### Décisions prises avec Stéphane
- L'écran de conversion propose **deux boutons** : « Créer la commande » et « Créer la commande et la facture ».
- L'**acompte** est proposé par une case « Acompte reçu » (montant du devis, mode de paiement au choix) : la commande
  est alors « partiellement payée », sinon impayée.
- **Expiration automatique** : un devis brouillon ou envoyé dont la validité est passée est affiché **et enregistré**
  « expiré » ; il ne peut être accepté ni converti sans repousser la date.
- Le **PDF du devis** reprend la présentation des factures (numéro, validité, délai, acompte, mention 293 B, « Bon
  pour accord », Partager et Imprimer).

### Limites connues et hypothèses
- Le devis est numéroté **à l'enregistrement** (pas de numéro pour un brouillon non enregistré) ; la suite repart à 1
  chaque année.
- Validité de **30 jours** proposée par défaut (modifiable) ; l'écran exige toujours une date.
- Le **client est facultatif** : sans client, le PDF indique « Client non précisé ».
- Seules les **lignes libres** existent dans un devis (pas de produit du catalogue) ; la conversion ne touche donc pas au
  stock.
- Un devis **ne se supprime pas** : on le marque « refusé ».
- Un devis expiré modifié avec une validité future redevient « brouillon ».
- Les notes d'un devis sont internes : elles ne s'impriment pas, mais passent dans la note de la commande.
- Le PDF d'un devis ne dépend pas du profil complet (seule la facture l'exige) ; il est refait quand le contenu imprimé
  change.
- Le schéma de la base n'a pas changé : pas de migration.

## [0.6.0] — Étape 6 : factures PDF et « Mon entreprise » (validée)

### Ajouté
- **Mon entreprise** (écran 22) : nom de l'entreprise, nom de l'entrepreneuse, adresse, code postal, ville, SIREN,
  téléphone, e-mail, conditions de paiement (par défaut « Paiement à réception de la facture. »), IBAN et message de
  remerciement (« Merci pour votre confiance ! » par défaut, modifiable ou vide). SIREN vérifié (9 chiffres, un SIRET
  est reconnu et expliqué), IBAN vérifié (forme et clé), quitter un formulaire modifié demande confirmation.
- **Créer la facture** sur l'écran d'une vente (`FactureRepository.creer`) : refusée tant que « Mon entreprise » est
  incomplet (message qui liste ce qui manque + bouton pour l'ouvrir ; aucun numéro consommé), sinon une facture par
  vente avec son numéro **FACT-AAAA-NNNN** attribué dans la même transaction que son enregistrement, le client, la
  mention « TVA non applicable, article 293 B du CGI », les conditions, l'IBAN et le remerciement **recopiés** à ce
  moment-là. Une vente annulée ne se facture pas ; une vente déjà facturée non plus (tant que sa facture n'est pas
  annulée).
- **PDF** (`genererFacturePdf`, paquets `pdf` et `printing`) : A4, fond blanc même en mode nuit, bande décorative rose
  et verte, logo monochrome, cartes émetteur et client, tableau (en-tête répété sur chaque page), remise, frais de
  port, total mis en valeur, mention 293 B, conditions, IBAN, remerciement, pied de page avec pagination. Polices
  Poppins embarquées. Rangé dans le dossier privé de l'application, un fichier par numéro.
- **Liste des factures** (écran 11, *Plus → Factures*) et **aperçu / détail** (écran 12) : aperçu du PDF, **Partager**
  (`share_plus`), **Imprimer** (dialogue d'impression d'Android), **Voir la vente**, **Annuler la facture**. Une
  facture s'ouvre aussi depuis la vente et depuis l'historique d'un client.
- **Annuler la facture** (`FactureRepository.annuler`) : la facture reste, marquée « annulée » ; son numéro reste
  utilisé ; la vente n'est pas touchée ; on peut établir une nouvelle facture (numéro suivant). Annuler la vente
  annule toujours sa facture.
- `VenteDetail.factures` / `factureEmise` : l'écran de vente affiche la facture en cours, ou le bouton pour la créer,
  et rappelle les factures annulées.
- La CI publie des exemples de PDF (facture complète, simple, longue) avec l'APK de test pour contrôler la mise en
  page à l'œil.

### Modifié
- Plus de « Bientôt disponible » pour les factures ; la ligne « Facture PDF : bientôt disponible. » de la vente est
  remplacée par la rubrique « Facture ».
- Les polices Poppins sont aussi déclarées comme ressources (lecture directe pour les PDF).
- Le texte des réglages indique « étape 6 sur 12 ».

### Décisions prises avec Stéphane
- Le bouton « Créer la facture » est **bloqué** tant que « Mon entreprise » est incomplet (message précis + accès
  direct au profil).
- Un bouton **« Annuler la facture »** annule la facture seule (pas la vente) ; le numéro reste utilisé.
- Le PDF utilise le **logo monochrome** de l'application.
- La facture est **à la demande**, avec son numéro attribué à ce moment-là (décidé à l'étape 5).

### Limites connues et hypothèses
- Pas d'**avoir** (note de crédit) : annuler une facture ne change qu'un statut. À discuter si nécessaire.
- Le PDF est fabriqué à la création et rangé sur le téléphone ; s'il manque, il est refait avec les coordonnées
  *actuelles* de l'entreprise (celles du client et les mentions restent celles de la création).
- Une facture annulée ne se partage ni ne s'imprime plus (son aperçu reste consultable).
- Le PDF n'indique ni paiements reçus ni acompte ; pas de date d'échéance (les conditions de paiement sont un texte).
- Un client de passage apparaît comme « Client de passage » sur la facture.
- Pas de recherche dans la liste des factures ni d'état de paiement dans la liste.
- Le schéma de la base n'a pas changé : pas de migration.

## [0.5.0] — Étape 5 : ventes et panier (validée)

### Ajouté
- Onglet **Vente** (écran 8) : client (fiche ou « client de passage »), recherche d'un produit, ajout au panier d'un
  appui (choix de la variante si le produit en a), ligne « Article ou prestation libre » (désignation, description,
  prix, quantité, objet ou prestation), barre « N articles · sous-total · Voir le panier ». Un produit épuisé,
  archivé ou marqué « épuisé » ne peut pas être mis au panier.
- **Panier** (écran 9) : quantités plafonnées au stock, retrait d'un article, remise en pourcentage ou en euros, frais
  de port, note, récapitulatif avec la mention « TVA non applicable, article 293 B du CGI ». Paiement : **Payée**,
  **Acompte** ou **Plus tard**, avec le mode (espèces, carte, virement, PayPal, chèque, autre). Le panier survit à la
  fermeture de l'écran et se vide quand la vente est validée.
- **Validation d'une vente** (`VenteRepository.valider`) : une seule transaction qui contrôle le client et les
  articles, décompte le stock, enregistre la vente, ses lignes (avec le coût matière du moment) et son paiement, puis
  calcule le statut de paiement. Si quelque chose échoue (stock épuisé entre-temps, acompte supérieur au total…), rien
  n'est enregistré.
- **Confirmation et détail d'une vente** (écran 10, aussi utilisé pour consulter une vente passée) : articles,
  totaux, statut de paiement, paiements, **encaissement du solde** (`VenteRepository.encaisser`, en plusieurs fois
  possible) et **annulation** (`VenteRepository.annuler`) : le stock est remis, un remboursement égal au net encaissé
  est enregistré, les factures émises pour la vente sont marquées annulées, et la vente reste dans l'historique.
- Règles du panier (`domain/calculs/panier.dart`, sans accès à la base) : `Panier` immuable, `LignePanier`,
  `PaiementSaisi`. Mêmes règles à l'écran et dans le dépôt de données.
- Une vente se rouvre depuis l'historique d'une fiche client (ventes et paiements) ou d'une fiche produit.
- Fiche produit : « Vendre » met le produit au panier et ouvre le panier ; « Ajouter au panier » reste sur la fiche et
  propose « Voir le panier ».

### Modifié
- Les tuiles « Nouvelle vente » (accueil) et l'onglet Vente ouvrent le vrai écran de vente (plus de « Bientôt
  disponible » pour la vente).
- Le texte des réglages indique « étape 5 sur 12 ».

### Décisions prises avec Stéphane
- **Facture à la demande** : le numéro FACT-… est attribué à l'étape 6, par un bouton « Créer la facture » sur la
  vente, pas à chaque vente.
- **Annulation et solde** : on peut annuler une vente et encaisser le solde dès cette étape.

### Limites connues
- Pas de **liste de toutes les ventes** : on les retrouve par la fiche d'un client ou d'un produit. À ajouter si utile.
- La **facture PDF** n'existait pas encore (arrivée à l'étape 6).
- Une vente validée ne se modifie pas : en cas d'erreur, on l'annule et on la refait.
- Les articles libres ne touchent jamais au stock. Le stock est contrôlé à la validation (tout ou rien).
- Le schéma de la base n'a pas changé : pas de migration.

## [0.4.0] — Étape 4 : clients

### Ajouté
- Onglet **Clients** (écran 6) : liste triée par nom affiché, recherche sans accents ni majuscules (nom, raison
  sociale, téléphone avec ou sans espaces, e-mail, adresse, ville, SIREN/SIRET, notes), filtres Particuliers /
  Professionnels / Archivés, étiquettes Professionnel / Archivé, état vide et message « aucun résultat ».
- **Fiche client** (écran 7) : coordonnées, historique des ventes (avec le total des ventes validées), paiements
  (remboursements compris), factures, devis et inscriptions aux cours, du plus récent au plus ancien (5 lignes puis
  « Voir tout »), archiver / restaurer avec confirmation, bandeau « Client archivé ».
- **Formulaire client** : choix Particulier / Professionnel, civilité, prénom, nom, raison sociale et SIREN/SIRET
  (professionnels seulement), téléphone, e-mail, adresse, code postal, ville, notes ; confirmation avant d'abandonner
  une saisie ; à la création, la fiche du nouveau client s'ouvre.
- Règles de saisie (`domain/regles_client.dart`) : e-mail, téléphone (6 à 15 chiffres), code postal (3 à 10 caractères,
  étranger accepté), SIREN (9 chiffres) ou SIRET (14 chiffres). Le formulaire et le dépôt de données appliquent les
  mêmes règles, avec les mêmes messages.
- Accès aux données : `observerClient` (fiche en direct), `historique` et `observerHistorique` (devis, ventes,
  factures, paiements et inscriptions d'un client, mis à jour automatiquement).
- Accueil : la tuile « Nouveau client » ouvre le formulaire (au lieu de « Bientôt disponible »).

### Modifié
- Le dépôt de clients refuse désormais un e-mail, un téléphone, un code postal ou un SIREN/SIRET mal formé
  (avant : seul le nom était contrôlé).
- Le composant d'étiquette (`Etiquette`) est partagé entre produits et clients (`core/widgets/etiquette.dart`).
- Le texte des réglages indique « étape 4 sur 12 ».

### Corrigé
- **Mises à jour en direct des fiches** (anomalie de l'étape 3, découverte par un test de l'étape 4) : Drift
  partage un même flux entre toutes les requêtes de même texte SQL, sans regarder les tables surveillées. Les flux
  du catalogue, de la fiche produit et de son historique, qui s'écrivaient tous `SELECT 1`, pouvaient donc se
  confondre : un écran ouvert ne se rafraîchissait plus quand une vente était ajoutée. `observerTables`
  (`data/database/flux_en_direct.dart`) distingue les flux par leurs tables ; test de non-régression ajouté.

### Limites connues
- Le « client de passage » (vente rapide sans fiche) est géré avec les ventes, à l'étape 5.
- L'historique d'un client reste vide tant que les ventes, factures, devis et cours ne peuvent pas être créés
  (étapes 5 à 8).
- Les contrôles de téléphone, de code postal et de SIREN/SIRET vérifient la **forme** (pas la clé de Luhn du SIRET,
  ni l'existence du numéro).
- Pas d'appel ni d'e-mail en un geste depuis la fiche (non demandé).
- Le schéma de la base n'a pas changé : pas de migration.

## [0.3.0] — Étape 3 : produits et stock

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
- Si Android ferme l'application pendant la prise d'une photo, celle-ci n'était pas récupérée (traité à l'étape 12).
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
