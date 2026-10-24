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
| 4 | Clients | terminée et validée |
| 5 | Ventes et panier | **à valider** (PR #5) |
| 6 | Factures PDF | à venir |
| 7 | Devis | à venir |
| 8 | Cours et inscriptions | à venir |
| 9 | Dépenses | à venir |
| 10 | Statistiques | à venir |
| 11 | Sauvegarde / export | à venir |
| 12 | Tests, corrections, optimisation de l'interface | à venir |

### Ce que contient l'étape 5 : ventes et panier

- **Onglet Vente** (écran 8) : choix du **client** (une fiche, ou « client de passage » pour une vente rapide sans
  fiche), recherche d'un produit, puis un appui sur le produit le met au panier. Un produit à variantes demande
  d'abord laquelle (couleur, taille…). **« Article ou prestation libre »** ajoute une ligne qui n'est pas au catalogue
  (création sur mesure, cours, frais…) : désignation, description, prix, quantité, objet ou prestation. La barre du
  bas montre le nombre d'articles et le sous-total.
- **Panier** (écran 9) : quantités (limitées au stock), retrait d'un article, **remise** (en % ou en €), **frais de
  port**, note sur la vente, récapitulatif (sous-total, remise, frais de port, total) avec la mention « TVA non
  applicable, article 293 B du CGI ». Le **paiement** se règle de trois façons : **Payée** (tout, maintenant),
  **Acompte** (une partie maintenant, le solde plus tard) ou **Plus tard**, avec le mode : espèces, carte, virement,
  PayPal, chèque ou autre. Le panier est conservé si on quitte l'écran.
- **Validation** : une confirmation, puis la vente est enregistrée **en une seule fois** avec ses lignes et son
  paiement, et le **stock est décompté** (tout ou rien : si un article manque entre-temps, rien n'est enregistré).
- **Confirmation / détail d'une vente** (écran 10) : articles, totaux, statut de paiement (payée, partiellement
  payée, impayée, remboursée, annulée) et paiements. On peut **encaisser le solde** (en une ou plusieurs fois) et
  **annuler la vente** : le stock est remis et un remboursement est enregistré ; la vente reste dans l'historique.
- **Historiques** : une vente se rouvre depuis l'historique d'une fiche client (ventes et paiements) ou d'une fiche
  produit.
- **Fiche produit** : « Vendre » met le produit au panier et ouvre le panier ; « Ajouter au panier » reste sur la
  fiche et propose « Voir le panier ».

À savoir : la **facture PDF** arrive à l'étape 6. Elle se crée à la demande, depuis une vente (bouton « Créer la
facture ») : le numéro FACT-… n'est attribué qu'à ce moment-là, pas à chaque vente. En attendant, la vente affiche
« Facture PDF : bientôt disponible. ». Il n'y a pas encore de liste de toutes les ventes : on les retrouve par la fiche
du client ou celle du produit (à discuter si une liste complète est utile).

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

À savoir : l'historique d'un client se remplit avec les ventes (étape 5) ; les factures, devis et cours viendront
aux étapes 6 à 8. Le « client de passage » (vente rapide sans fiche) se choisit dans l'onglet Vente.

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

À savoir : depuis l'étape 5, « Vendre » et « Ajouter au panier » alimentent le panier, et l'historique des ventes
de la fiche produit se remplit.

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
