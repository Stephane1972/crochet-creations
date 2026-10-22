# Feuille de route

Le développement avance par petites étapes que l'on valide une à une. Chaque étape = une branche,
des commits clairs et une pull request.

## Version 1 : l'application complète, hors ligne

Objectif : gérer toute l'activité sans connexion ni serveur.

| Étape | Contenu | Écrans concernés |
|------:|---------|------------------|
| 1 | Initialisation Flutter, thème rose/vert, mode jour/nuit, navigation, logo, splash, accueil | 1, 2 (maquette), 21 (thème) |
| 2 | Base de données SQLite (15 tables), modèles, migrations versionnées, repositories ; enregistrement du mode jour/nuit | — |
| 3 | Produits et stock : catalogue, fiche, ajout/modification, duplication, archivage, alertes de stock, photos | 3, 4, 5 |
| 4 | Clients : liste, fiche, historique, « client de passage » | 6, 7 |
| 5 | Ventes et panier : choix du client, quantités, remise, frais de port, paiement, décrémentation du stock | 8, 9, 10 |
| 6 | Factures PDF : numérotation `FACT-AAAA-NNNN`, mention art. 293 B, impression, partage ; profil « Mon entreprise » | 11, 12, 22 |
| 7 | Devis : lignes libres, validité, acompte, statuts, conversion en facture | 13, 14, 15 |
| 8 | Cours et inscriptions : places, liste d'attente, paiement, reçu | 16, 17, 18 |
| 9 | Dépenses : catégories, photo du ticket, produit concerné | 19 |
| 10 | Statistiques et alertes de franchise de TVA (85 000 € biens / 37 500 € services) | 20 |
| 11 | Sauvegarde automatique, export CSV et JSON, restauration | 23 |
| 12 | Tests, corrections, optimisation de l'interface | tous |

Les numéros d'écrans renvoient à la liste du cahier des charges (1 à 23).
Hypothèse à confirmer : le profil « Mon entreprise » (écran 22) est construit à l'étape 6, car les factures en ont besoin.

### État

- [x] Étape 1 : terminée et validée (PR #1)
- [x] Étape 2 : terminée et validée (PR #2)
- [x] Étape 3 : terminée et validée (PR #3)
- [x] Étape 4 : terminée, **en attente de validation** (PR #4)
- [ ] Étapes 5 à 12

## Version 2 : confort et échanges (propositions, non engagées)

Idées à discuter après la version 1 :

- sauvegarde sur Google Drive (la version 1 reste sans cloud) ;
- rappels de paiement pour les factures impayées ;
- export pour la comptabilité (livre des recettes, registre des achats) ;
- modèles de devis et de factures personnalisables (messages, conditions) ;
- code de verrouillage de l'application.

## Version 3 : aller plus loin (propositions, non engagées)

- synchronisation entre plusieurs appareils (téléphone et tablette) ;
- lien vers une boutique en ligne ou un catalogue partageable ;
- étiquettes avec QR code pour les stands et marchés ;
- version tablette de l'interface.
