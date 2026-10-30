# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.9.0] — Étape 9 : dépenses (en attente de validation)

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
  `common/choix_photo.dart` : la feuille « Prendre une photo / Galerie / Retirer », commune aux formulaires.
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
