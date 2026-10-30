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
| 5 | Ventes et panier | terminée et validée |
| 6 | Factures PDF et « Mon entreprise » | terminée et validée |
| 7 | Devis : lignes libres, validité, acompte, statuts, conversion en facture | terminée et validée |
| 8 | Cours et inscriptions : places, liste d'attente, paiement, facture par inscrit | terminée et validée |
| 9 | Dépenses : catégories, photo du ticket, produit concerné | **à valider** (PR #9) |
| 10 | Statistiques | à venir |
| 11 | Sauvegarde / export | à venir |
| 12 | Tests, corrections, optimisation de l'interface | à venir |

### Ce que contient l'étape 9 : dépenses

- **Liste des dépenses** (écran 19, *Plus → Dépenses*) : **un mois à la fois** (flèches ‹ › pour changer de mois, pas de
  mois à venir), avec en haut le **total du mois** et le nombre de dépenses. Des pastilles filtrent par **catégorie**
  (laine / fil, fournitures, emballage, stand / marché, transport, publicité, matériel, autre) : le total se réduit alors
  à la catégorie choisie. L'**icône d'archive** de la barre du haut bascule vers les dépenses mises de côté (et revient). La plus récente est en haut.
- **Nouvelle dépense / modifier** : **date** (aujourd'hui par défaut, jamais dans le futur), **catégorie**, **montant**
  (supérieur à 0), **fournisseur**, **description**, **photo du ticket** (appareil photo ou galerie, copiée dans
  l'application) et **produit concerné** (facultatif). Un appui sur une ligne de la liste ouvre la dépense pour la modifier.
- **Produit concerné** : simple information (ex. la laine d'un doudou). Il n'est affiché que sur la dépense ; il ne change
  ni le coût matière du produit, ni son stock, ni sa fiche.
- **Archiver / restaurer** : une dépense **ne se supprime pas**. *Menu ⋮ → « Archiver la dépense »* la retire de la liste
  et des totaux ; elle reste récupérable avec l'icône d'archive de la liste (*⋮ → « Restaurer la dépense »*).
- Les totaux **détaillés par catégorie** et la marge estimée viendront avec les statistiques (étape 10).

### Ce que contient l'étape 8 : cours et inscriptions

- **Liste des cours** (écran 16, *Plus → Cours*) : « À venir » (du plus proche au plus lointain), « Passés » et
  « Archivés ». Chaque ligne montre la photo, le titre, la date et l'heure, **« 3 / 6 places »** (ou **« Complet »**),
  le nombre de personnes **en attente**, le prix et l'étiquette « Annulé » le cas échéant.
- **Créer / modifier un cours** : titre, description, **date et heure**, **durée**, lieu, **prix par personne** (0 = gratuit),
  **nombre de places**, niveau (débutant, intermédiaire, avancé, tous niveaux), **matériel inclus ou non** et une photo.
  On ne peut pas descendre le nombre de places sous celui des personnes déjà confirmées ; modifier le prix ne change
  pas celui des personnes déjà inscrites.
- **Fiche du cours** (écran 17) : les informations, puis **« Inscrits »** avec l'état du paiement de chacun (Payé,
  Acompte versé avec le reste à payer, À payer, Remboursé), la **« Liste d'attente »** (numérotée) et les
  **« Inscriptions annulées »**. Un appui sur une personne ouvre ses actions : **voir la vente et la facture**,
  **confirmer** (liste d'attente) ou **annuler l'inscription**.
- **Inscrire quelqu'un** (écran 18) : on choisit le client (une fiche est obligatoire), on peut **changer le prix pour
  cette personne**, puis on règle comme pour une vente : **payée**, **acompte** ou **plus tard**, avec le mode de paiement.
  L'inscription crée une **vente** d'une ligne « Cours : titre » (sans effet sur le stock) : la facture se crée ensuite
  avec le bouton habituel « Créer la facture » de la vente. Un cours gratuit n'encaisse rien.
- **Liste d'attente manuelle** : quand le cours est complet, la personne passe en liste d'attente, **sans vente ni
  paiement**. Quand une place se libère, rien n'est automatique : on **confirme la première personne** de la liste
  (le paiement se règle à ce moment-là). Seule la première peut être confirmée, et seulement si une place est libre.
- **Annuler une inscription** : si de l'argent a déjà été reçu, l'application demande **à chaque fois** :
  **« Annuler et rembourser »** (la vente est annulée et le paiement remboursé) ou **« Annuler en gardant le
  paiement »** (la vente et l'argent restent tels quels ; le solde éventuel reste dû, la vente peut être annulée plus
  tard depuis son écran). Sans argent reçu, la vente de la personne est simplement annulée.
- **Annuler un cours** : plus personne ne peut s'y inscrire, mais les **inscriptions restent affichées** : on les
  annule **une par une** (avec ou sans remboursement). **« Rétablir le cours »** le rouvre. Un cours **ne se
  supprime pas** : un cours terminé ou annulé peut être **archivé** (et restauré).
- Dans la fiche d'un client, l'historique des cours ouvre la fiche du cours.

### Ce que contient l'étape 7 : devis

- **Liste des devis** (écran 13, *Plus → Devis*) : le plus récent d'abord, avec son numéro **DEVIS-AAAA-NNNN**, le
  client, la date, le total et son **statut** : brouillon, envoyé, accepté, refusé ou expiré.
- **Créer / modifier un devis** (écran 14) : client facultatif, **lignes libres** (désignation, description détaillée,
  quantité, prix), **remise** (en % ou en €), **frais de port**, **date de validité** (30 jours par défaut, à
  modifier), **délai de réalisation**, **acompte demandé** et notes pour vous (non imprimées). Le numéro est attribué
  à l'enregistrement.
- **Statuts** : un brouillon peut être marqué envoyé, accepté ou refusé ; un devis envoyé peut être accepté ou
  refusé ; un devis accepté (pas encore converti) peut encore être refusé. Un devis **dont la date de validité est passée devient
  « expiré »** tout seul : il ne peut plus être accepté ni converti tant qu'on n'a pas repoussé la date (en le
  modifiant, il redevient brouillon).
- **Le PDF du devis** : même présentation que les factures, avec la validité, le délai, l'acompte demandé (et l'IBAN
  pour le régler), la mention « TVA non applicable, article 293 B du CGI » et un cadre **« Bon pour accord »** à
  signer. **Partager** et **Imprimer** comme pour une facture.
- **Convertir un devis** (écran 15) : deux boutons, **« Créer la commande »** et **« Créer la commande et la
  facture »**. Si le devis demande un acompte, la case **« Acompte reçu »** enregistre ce premier paiement (avec son
  mode) : la commande est alors « partiellement payée », sinon elle est impayée. Le devis passe à **« accepté »**,
  est marqué « converti en commande » et renvoie vers la commande. Si « Mon entreprise » est incomplet, **rien n'est créé** et un message dit ce qui manque.

À savoir : un devis ne se supprime pas (on le marque « refusé »). La commande issue d'un devis est une vente
validée **sans effet sur le stock** (lignes libres) ; le numéro du devis figure dans sa note.

### Ce que contient l'étape 6 : factures PDF et « Mon entreprise »

- **Mon entreprise** (écran 22, *Plus → Réglages → Mon entreprise*) : nom de l'entreprise, votre nom, adresse, code
  postal, ville, **SIREN** (9 chiffres, vérifié ; un SIRET est reconnu et expliqué), téléphone, e-mail, **conditions
  de paiement** (par défaut « Paiement à réception de la facture. »), **IBAN** facultatif (vérifié) et **message de
  remerciement** personnalisable. La mention « TVA non applicable, article 293 B du CGI » est automatique.
- **Créer la facture** : bouton sur l'écran d'une vente. Tant que le nom, l'adresse, le code postal, la ville et un
  SIREN valide ne sont pas renseignés, la facture n'est pas créée : un message liste ce qui manque et propose
  d'ouvrir « Mon entreprise » (aucun numéro n'est consommé). Sinon la facture reçoit son numéro
  **FACT-AAAA-NNNN** (unique, dans l'ordre, une suite par année) et s'ouvre aussitôt.
- **Le PDF** : fond blanc (même en mode nuit), bande rose et verte, logo monochrome, vos coordonnées, celles du
  client, tableau des articles (quantités, prix unitaires, totaux), remise, frais de port, **total mis en valeur**,
  mention de franchise de TVA, conditions de paiement, IBAN et remerciement s'ils sont renseignés, pied de page
  numéroté. Une longue facture continue sur plusieurs pages. Les coordonnées du client et les mentions sont
  **recopiées à la création** : modifier plus tard la fiche client ou « Mon entreprise » ne change pas une facture
  déjà créée.
- **Liste des factures** (écran 11, *Plus → Factures*) : la plus récente d'abord, avec client, date, total et
  l'étiquette « Annulée » le cas échéant.
- **Aperçu et détail** (écran 12) : le PDF tel qu'il sera envoyé, puis **Partager** (messagerie, e-mail…),
  **Imprimer**, **Voir la vente** et **Annuler la facture**. Une facture se rouvre aussi depuis la vente et depuis
  l'historique du client.
- **Annuler la facture** : la facture reste dans la liste, marquée « annulée » ; son numéro reste utilisé ; **la
  vente n'est pas annulée** (stock et paiements ne changent pas) et on peut créer une nouvelle facture pour la même
  vente. Annuler une *vente* annule aussi sa facture.

À savoir : le PDF est rangé sur le téléphone à la création ; s'il disparaît (fichier effacé, sauvegarde restaurée
sans les PDF), il est refait à l'ouverture de la facture avec les coordonnées *actuelles* de l'entreprise. Une
facture annulée ne peut plus être partagée ni imprimée. Le PDF n'affiche pas les paiements reçus.

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

À savoir : la **facture PDF** se crée à la demande, depuis une vente (étape 6, ci-dessus) : le numéro FACT-… n'est
attribué qu'à ce moment-là, pas à chaque vente. Il n'y a pas encore de liste de toutes les ventes : on les retrouve
par la fiche du client ou celle du produit (à discuter si une liste complète est utile).

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

À savoir : l'historique d'un client se remplit avec les ventes (étape 5) ; les factures (étape 6), devis et cours viendront
aux étapes suivantes. Le « client de passage » (vente rapide sans fiche) se choisit dans l'onglet Vente.

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
