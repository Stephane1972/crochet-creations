# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.6.0] — Étape 6 : factures PDF et « Mon entreprise » (en attente de validation)

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
