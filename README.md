# Un p’tit crochet dans les stocks

Application Android de gestion pour une créatrice auto-entrepreneuse qui vend des objets en crochet,
des doudous, des boucles d'oreilles, des accessoires faits main, des créations personnalisées et des
cours de crochet.

Elle permet de gérer le **catalogue et le stock**, les **clients**, les **ventes**, les **factures PDF**,
les **devis**, les **cours et inscriptions**, les **dépenses**, des **statistiques simples**
et les **sauvegardes**. Elle fonctionne **entièrement hors ligne**, sans serveur ; l'envoi des fichiers vers **Google Drive**
est une option, qui ne part que sur demande.

Elle existe aussi en **version Windows** (un dossier `.zip` portable, la même interface dans une fenêtre) : voir « Version Windows » plus bas.
La version Android reste la version de référence, inchangée.

> Nom de l'application : « Un p’tit crochet dans les stocks » (elle s'appelait « Crochet & Créations » : le nom du dépôt GitHub
> et le nom technique `crochet_creations` n'ont pas changé).

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
| 9 | Dépenses : catégories, photo du ticket, produit concerné | terminée et validée |
| 10 | Statistiques et alertes de franchise de TVA | terminée et validée |
| 11 | Sauvegarde, export CSV / JSON et restauration | terminée et validée |
| 12 | Tests, corrections, optimisation de l'interface | terminée et validée |

### Nom et logo de l'application (après l'étape 12)

- **Nouveau nom** : « Un p’tit crochet dans les stocks », affiché partout : sous l'icône Android, écran de démarrage, réglages,
  sujets des partages (sauvegardes, exports).
- **Nouveau logo** (la fillette aux pelotes) : **icône de lancement Android** (icône adaptative, sur fond rose) et **logo dans
  l'application** (écran de démarrage, accueil, réglages). L'image de départ est `assets/icon/logo_source.png` ; la commande
  `python3 tool/generate_icons.py` en refait les images dérivées.
- Les **factures et devis** portent le **logo de l'entreprise** (« Un p’tit crochet par ici ») ; le nom imprimé à côté est celui
  saisi dans *Mon entreprise*.

### Ce que contient l'étape 12 : finitions

- **Photo perdue retrouvée** : si Android ferme l'application pendant la prise d'une photo (cela arrive quand le téléphone
  manque de mémoire), la photo n'est plus perdue. Au prochain démarrage, l'application la récupère ; la **prochaine fois
  qu'on choisit une photo** (produit, cours ou ticket de dépense), la feuille propose en premier **« Utiliser la photo
  retrouvée »**. Le formulaire, lui, n'est pas restauré : il faut le ressaisir. On peut ignorer la proposition et
  choisir une autre photo ; la photo retrouvée est alors oubliée.
- **Une seule feuille « choix de photo »** pour les trois formulaires (produit, cours, ticket de dépense) : les textes et le
  comportement sont identiques partout.
- Aucun changement de schéma de la base, aucune nouvelle dépendance.

### Supprimer un client ou un produit (après l'étape 12)

- **Où** : *fiche client* ou *fiche produit* → menu **⋮** → **Supprimer**. L'**archivage** (qui retire seulement de la liste)
  reste proposé à côté ; il est plus prudent, car on peut restaurer.
- **Jamais utilisé** : une confirmation simple, puis c'est supprimé (le produit emporte ses variantes et ses photos).
- **Déjà utilisé** : une confirmation renforcée dit où l'élément apparaît (par exemple « 2 ventes, 1 facture et 1 devis ») ;
  il faut choisir **Supprimer définitivement**. L'**historique est conservé** : les ventes et devis d'un client supprimé
  gardent son nom (« Camille Martin (client supprimé) »), les factures gardent son nom, son adresse et son SIRET ; les ventes et
  devis d'un produit supprimé gardent la désignation, la quantité et le prix. Les dépenses qui désignaient le produit restent.
- **Exception** : un client **inscrit à un cours** ne peut pas être supprimé ; l'application propose de l'**archiver**.
- **Attention** : c'est **définitif** (seule une sauvegarde permet de revenir en arrière), et les coordonnées et notes du client
  disparaissent avec sa fiche.
- Le schéma de la base passe en **version 2** (deux colonnes `client_nom`, migration automatique) ; les anciennes sauvegardes
  se restaurent normalement.

### Catégories de produits modifiables (après l'étape 12)

- **Depuis « Nouveau produit »** : la liste **Catégorie** se termine par **+ Nouvelle catégorie**. On tape le nom, la catégorie
  est créée et choisie tout de suite. Elle reste disponible même si on abandonne le formulaire.
- **Écran « Catégories »** (*Plus → Réglages → Catégories*) : la liste avec le nombre de produits de chaque catégorie, le bouton
  **Nouvelle catégorie**, et pour chaque ligne **Renommer** (le nom change partout : liste, fiche, filtres, statistiques) et
  **Supprimer**. Les cinq catégories d'origine se renomment ou se suppriment comme les autres.
- **Supprimer une catégorie** : vide, une simple confirmation. Qui contient des produits (archivés compris), l'application demande
  **dans quelle catégorie les déplacer** (il faut en choisir une), puis déplace et supprime. Aucun produit n'est jamais perdu ni
  laissé sans catégorie. Si c'est la dernière catégorie, il faut d'abord en créer une autre.
- Deux catégories ne peuvent pas porter le même nom (sans tenir compte des majuscules, des accents ni des espaces) ; 60 caractères
  au plus.
- Le schéma de la base passe en **version 3** (nouvelle table `categories_produit`, migration automatique, aucun produit modifié) ;
  les anciennes sauvegardes se restaurent normalement.

### Lieux de vente (après l'étape 12)

- **Un lieu sur chaque vente** (marché, salon, boutique, vente en ligne, ou un lieu à vous). Quatre lieux sont créés au départ
  (Marché, Salon, Boutique, Vente en ligne) ; ils se renomment ou se suppriment comme les autres.
- **Dans le panier** : la carte **Lieu de vente** ouvre la liste ; **+ Nouveau lieu de vente** en crée un et le choisit aussitôt.
  On peut valider sans choisir : la vente est alors **« Non renseigné »**.
- **Après coup** : dans le détail d'une vente (même annulée), la même carte permet de préciser ou de corriger le lieu. Seul le lieu
  change : ni montants, ni stock, ni facture.
- **Écran « Lieux de vente »** (*Plus → Réglages → Lieux de vente*) : la liste avec le nombre de ventes de chaque lieu, **Nouveau
  lieu**, **Renommer** (le nom change partout) et **Supprimer**. Un lieu qui a des ventes ne se supprime qu'en choisissant **où les
  déplacer** (un autre lieu, ou « Non renseigné ») : aucune vente n'est jamais supprimée.
- **Les ventes déjà enregistrées restent « Non renseigné »** : rien n'est rattaché à un lieu sans que vous l'ayez choisi.
- Deux lieux ne peuvent pas porter le même nom (sans tenir compte des majuscules, des accents ni des espaces) ; 60 caractères au plus ;
  « Non renseigné » est réservé.
- L'**export CSV** des ventes a une colonne « Lieu de vente ». Les **statistiques par lieu** sont dans l'écran *Analyse détaillée* (voir plus bas).
- Le schéma de la base passe en **version 4** (table `lieux_vente`, colonne `ventes.lieu_id`, migration automatique) ; les
  anciennes sauvegardes se restaurent normalement.

### Bloc-notes (après l'étape 12)

- **Un bloc-notes** (*Plus → Bloc-notes*) : des notes avec un **titre** (obligatoire), un **texte** (facultatif) et une
  **catégorie** (facultative). La note modifiée en dernier est en haut de la liste.
- **Deux catégories au départ** : **Futures commandes** et **Documents entreprise** ; vous créez les vôtres. Une note sans
  catégorie est rangée dans **« Sans catégorie »**. En haut de la liste, des **filtres** : Toutes, chaque catégorie, Sans catégorie.
- **Écrire une note** : bouton **Nouvelle note**, puis titre, catégorie (**+ Nouvelle catégorie** la crée et la choisit tout de
  suite) et texte, puis **Enregistrer**. Appuyer sur une note l'ouvre pour la modifier ; son menu **Plus d'actions** la **supprime**
  (après confirmation, définitivement).
- **Écran « Catégories de notes »** (*Plus → Réglages → Catégories de notes*, ou l'icône d'étiquette du bloc-notes) : la liste avec
  le nombre de notes de chaque catégorie, **Nouvelle catégorie**, **Renommer** et **Supprimer**. Une catégorie qui a des notes ne
  se supprime qu'en choisissant **où les déplacer** (une autre catégorie, ou « Sans catégorie ») : aucune note n'est jamais supprimée.
- Deux catégories ne peuvent pas porter le même nom (sans tenir compte des majuscules, des accents ni des espaces) ; 60 caractères
  au plus ; « Sans catégorie » est réservé.
- Les **pièces jointes** (photos, vidéos, documents) sont décrites plus bas (étape 4 du plan d'évolution).
- Le schéma de la base passe en **version 5** (tables `categories_note` et `notes`, migration automatique) ; la **sauvegarde**
  contient aussi le bloc-notes, et les anciennes sauvegardes se restaurent normalement.

### Pièces jointes des notes (étape 4 de l'évolution)

- Dans l'écran d'une note, la section **Pièces jointes** : **Ajouter une pièce jointe** propose *Prendre une photo*, *Choisir une
  photo dans la galerie*, *Filmer une vidéo*, *Choisir une vidéo dans la galerie* et *Choisir un document (PDF, Word, tableur…)*.
- **Limites, affichées avant l'ajout** : 100 Mo au plus par photo et par document, 500 Mo au plus par vidéo, 50 pièces jointes au plus
  par note. Un fichier trop gros est refusé avec un message qui dit la limite ; rien n'est copié.
- Le fichier est **copié dans l'application** (la galerie peut être vidée sans rien perdre). Une **photo** s'ouvre en plein écran dans
  l'application ; une **vidéo** ou un **document** s'ouvre dans l'application du téléphone qui sait le lire.
- **Retirer** une pièce jointe, ou **supprimer la note**, efface aussi le fichier du téléphone — mais seulement une fois la note enregistrée :
  en abandonnant la saisie, rien n'est perdu.
- La liste des notes indique le **nombre de pièces jointes** de chaque note.
- Le schéma de la base passe en **version 6** (table `pieces_jointes_note`, migration automatique). La **sauvegarde** emporte les pièces
  jointes (dossier `notes_pieces_jointes`) ; si l'un de ces fichiers manque sur le téléphone, la sauvegarde est signalée **incomplète**.
  Les anciennes sauvegardes se restaurent normalement (sans pièce jointe). Nouvelle dépendance gratuite : `open_filex`.

### Analyse détaillée des statistiques (étape 5 de l'évolution)

- *Plus → Statistiques → Analyse détaillée* : l'**argent encaissé** regroupé **par année, par mois, par lieu de vente ou par catégorie**,
  en **graphique** (une barre par ligne) et en **tableau** (argent encaissé, coût de la matière, marge estimée, total).
- Quatre **filtres qui se croisent** : *Année* (ou « Toutes les années »), *Mois*, *Lieu de vente* (dont « Non renseigné ») et
  *Catégorie* (dont « Sans catégorie »). Par exemple : les doudous vendus au Marché, mois par mois, en 2026.
- Les **mêmes règles que l'écran Statistiques** : un paiement compte à la date où il est reçu, un remboursement se déduit, une remise est
  répartie sur les lignes, le coût de la matière est celui relevé à la vente. Les chiffres sont identiques, au centime près, à ceux de
  l'écran Statistiques pour une même période. « Sans catégorie » regroupe les lignes libres, les cours et les frais de port.
- Aucune dépendance ajoutée (les barres sont dessinées avec Flutter), aucun changement de la base.

### Google Drive, partie 1 (étape 6 de l'évolution)

- *Réglages → Google Drive* : **Se connecter à Google**, puis **Envoyer maintenant** copie sur votre Drive, dans le dossier
  « Un p’tit crochet dans les stocks », les **photos des produits**, les **factures**, les **devis** et les **pièces jointes des notes**
  (quatre sous-dossiers : « Photos des produits », « Factures », « Devis », « Notes - pièces jointes »).
- **Rien ne part tout seul** : l'envoi se lance par le bouton, et seulement par lui. L'envoi automatique des *sauvegardes* est un réglage à part (partie 2), désactivé au départ.
- **Vérifier** compare le téléphone et Drive **sans rien envoyer** : « 12 fichiers à envoyer (8,4 Mo) », dossier par dossier.
- **Drive est la mémoire** : ce qui est déjà sur Drive (même nom, même taille ; pour les factures et les devis, même contenu) n'est pas
  renvoyé. Un téléphone neuf ou une application réinstallée ne renvoie donc rien pour rien. Une facture ou un devis régénéré remplace le
  fichier de Drive (Drive garde l'ancienne version dans l'historique du fichier).
- **Un fichier qui échoue n'empêche pas les autres** ; l'envoi s'arrête seulement si la connexion à Google est perdue ou après trois
  échecs de suite. Le **bilan du dernier envoi** (date, fichiers envoyés, déjà sur Drive, échecs détaillés) reste affiché ; relancer
  l'envoi ne renvoie que ce qui manque. **Arrêter** interrompt l'envoi à la fin du fichier en cours.
- **Jamais de suppression, jamais de partage tout seul** : l'application ne supprime aucun fichier sur Drive et ne partage rien d'elle-même
  (le partage, à la demande, vient avec l'étape 8). Elle ne demande à Google que le droit de voir et de gérer **les fichiers qu'elle a
  elle-même créés** (`drive.file`), jamais le reste de votre Drive.
- Gardez l'application ouverte et l'écran allumé pendant un gros envoi (les vidéos peuvent être lourdes). Se déconnecter n'efface rien sur Drive.
- Aucun changement de la base (schéma 6) ni de la sauvegarde. Nouvelles dépendances gratuites : `google_sign_in`, `googleapis`, `http`. La
  permission Internet est ajoutée à l'application (elle ne sert qu'à cet envoi).

#### Configurer Google Cloud (une seule fois, gratuit, environ 15 minutes)

Pour qu'une application Android puisse demander à Google l'accès à votre Drive, Google exige qu'elle soit déclarée dans un « projet »
Google Cloud. C'est gratuit : aucune carte bancaire n'est demandée pour l'API Drive et la connexion. Sans cette configuration,
l'application fonctionne normalement ; l'écran *Google Drive* indique simplement que la connexion n'est pas encore configurée.
Les noms ci-dessous sont ceux de la console Google Cloud (en français ou en anglais selon votre compte) ; ils changent parfois un peu.

1. **Ouvrir la console** : https://console.cloud.google.com, avec le compte Google dont vous voulez utiliser le Drive. Accepter les
   conditions si Google les propose.
2. **Créer un projet** : en haut, le sélecteur de projet → **Nouveau projet** → nom « Un p'tit crochet » → **Créer**, puis le choisir.
3. **Activer l'API Google Drive** : menu ☰ → **API et services** → **Bibliothèque** → chercher « Google Drive API » → **Activer**.
4. **Configurer l'écran de consentement** (menu ☰ → **API et services** → **Écran de consentement OAuth**, aussi appelé *Google Auth
   Platform*) → **Commencer** :
   - *Nom de l'application* : « Un p'tit crochet dans les stocks » ; *adresse e-mail d'assistance* : la vôtre ;
   - *Audience* (public) : **Externe** ; *coordonnées* : votre adresse e-mail ; accepter la politique de données → **Créer**.
5. **Déclarer le seul droit demandé** : **Accès aux données** (*Data Access*) → **Ajouter ou supprimer des niveaux d'accès** → cocher
   (ou coller dans « Ajouter manuellement ») `https://www.googleapis.com/auth/drive.file` (« Afficher, modifier, créer et supprimer
   uniquement les fichiers Google Drive spécifiques que vous utilisez avec cette application ») → **Enregistrer**. Ne cochez aucun autre droit.
6. **Publier l'application** : **Audience** → **Publier l'application** → confirmer. En mode « Test », Google fait **expirer l'autorisation
   au bout de 7 jours** (il faudrait se reconnecter chaque semaine). Avec ce seul droit, aucune vérification par Google n'est nécessaire ;
   et publier ne rend rien public : l'application ne sert qu'à vous. Si Google propose la vérification, vous pouvez ignorer.
   (Si vous ne publiez pas : ajoutez votre adresse comme **utilisateur test** dans *Audience*, sinon la connexion sera refusée.)
7. **Créer l'accès « Android »** : **Clients** → **Créer un client** → type d'application **Android** :
   - *Nom* : « Android » ;
   - *Nom du package* : `fr.crochetcreations.crochet_creations` (exactement) ;
   - *Empreinte du certificat SHA-1* : celle affichée dans les **notes de la pré-version** de l'APK (voir « Signature de
     l'application » plus bas : ligne « Certificat SHA-1 »). C'est celle de la clé de signature stable ; elle ne change plus d'un APK à l'autre.
   → **Créer**.
8. **Créer l'accès « Application Web »** : **Clients** → **Créer un client** → type **Application Web** → nom « Web » → **Créer**.
   Copier l'**ID client** affiché (il se termine par `.apps.googleusercontent.com`). Ignorer le « code secret » : il ne sert pas ici.
9. **Donner l'ID client Web à l'application** : le plus simple est de le **coller dans l'application**, sans nouvelle version :
   *Réglages → Google Drive → carte « ID client Web Google »* → coller l'ID → **Enregistrer l'ID**, puis *Se connecter à Google*.
   L'application nettoie ce qui est collé (espaces, retours à la ligne, guillemets), vérifie qu'il a la forme d'un ID client
   (`…apps.googleusercontent.com`) et **refuse un « code secret »** (`GOCSPX-…`). L'ID est gardé sur le téléphone (un petit fichier, hors de la
   base et des sauvegardes : après un changement de téléphone, il est à coller de nouveau). *Oublier l'ID enregistré* revient à celui fourni
   avec l'application, s'il y en a un. Si l'on corrige un ID **après** avoir essayé de se connecter, Google ne se laisse configurer qu'une fois
   par lancement : l'application demande alors de la fermer complètement (la retirer des applications récentes), puis de la rouvrir.
   Autres façons de le donner : l'écrire dans `lib/core/constants/google_config.dart` (constante `_clientWebParDefaut`) ou, pour une
   construction locale, ajouter `--dart-define=GOOGLE_WEB_CLIENT_ID=VOTRE_ID` à `flutter run` / `flutter build`. L'ID saisi dans l'application
   passe avant celui fourni avec elle. Ce n'est **pas un secret** : il est visible dans toute application Android qui utilise Google. Ne
   publiez en revanche jamais un « code secret » ni un fichier de clé.

**Si la connexion échoue** : l'écran *Google Drive* affiche la raison. Les causes habituelles sont (a) le **nom du package** ou
l'**empreinte SHA-1** de l'accès Android qui ne correspondent pas à l'APK installé (recopier la SHA-1 des notes de la pré-version,
sans espace), (b) l'**ID client Web** manquant ou celui d'un autre type d'accès, (c) l'**API Google Drive** non activée dans le projet,
(d) l'application non publiée et votre adresse absente des utilisateurs test. Un changement dans la console peut mettre quelques
minutes à se propager.

### Google Drive, partie 2 (étape 7 de l'évolution)

- *Réglages → Google Drive → Sauvegarder mes données sur Drive* (visible une fois connecté à Google) : **Sauvegarder maintenant sur
  Drive** envoie sur votre Drive, dans le dossier « Sauvegardes » (sous « Un p’tit crochet dans les stocks »), une **petite sauvegarde
  datée** de toutes vos données (produits, clients, ventes, factures, devis, cours, dépenses, notes, réglages) avec la **liste de vos
  photos, PDF et pièces jointes**. Les photos et documents eux-mêmes **ne sont pas recopiés dans la sauvegarde** : ils sont déjà dans leurs
  dossiers Drive (partie 1), qui sont **complétés avant chaque sauvegarde**. Une sauvegarde pèse donc quelques dizaines de Ko, pas des Mo.
- La sauvegarde se fait en trois étapes, avec une barre de progression : (1) envoi des fichiers qui ne sont pas encore sur Drive,
  (2) lecture des données et préparation de la sauvegarde, (3) envoi puis **vérification sur Drive** (le fichier est retrouvé, avec la bonne
  taille). **Arrêter** (pendant l'étape 1) interrompt l'envoi ; dans ce cas, aucune sauvegarde des données n'est ajoutée, pour ne jamais
  annoncer une sauvegarde dont les fichiers manqueraient.
- **Si rien n'a changé** depuis la dernière sauvegarde, aucune nouvelle sauvegarde n'est ajoutée (« Rien de neuf : la dernière sauvegarde
  sur Drive est à jour ») ; l'écran indique la date de la dernière vérification.
- **Un fichier qui n'a pas pu partir** n'empêche pas la sauvegarde, mais n'est **pas listé** dedans, et l'écran le dit (« 1 fichier n’a pas pu
  partir sur Drive… Relancez la sauvegarde »). Relancer ajoute une sauvegarde qui le liste.
- **Envoi automatique** (interrupteur, **désactivé au départ**) : à l'ouverture de l'application, **au plus une fois par jour**, et seulement
  si quelque chose a changé, la sauvegarde sur Drive se fait toute seule, à condition d'être connecté à Google. Depuis la version 0.25.0,
  l'envoi se fait aussi quand on ferme l'application (voir « Synchroniser le téléphone et le PC » plus bas). Un échec (pas de réseau) est dit
  sur l'écran *Google Drive* et retenté à l'ouverture suivante.
- **Tout est gardé** : chaque sauvegarde reste sur Drive, l'application n'en supprime aucune (vous pouvez les supprimer vous-même dans Drive).
- **Restaurer / changer de téléphone** : *Google Drive → Restaurer depuis Drive…* liste les sauvegardes (la plus récente en premier).
  Sur un téléphone neuf : installez l'application (même signature, voir plus bas), **connectez-vous au même compte Google**, puis restaurez la
  plus récente. Avant de remplacer quoi que ce soit, l'application **télécharge la petite sauvegarde**, dit ce qu'elle contient (nombre
  d'enregistrements, de fichiers, taille) et **demande confirmation**. Elle **retélécharge ensuite chaque photo, PDF et pièce jointe depuis
  leurs dossiers Drive et les contrôle** (taille et empreinte SHA-256) **avant de toucher à vos données**. Si le réseau coupe, **rien n'est
  modifié** et vous pouvez recommencer ; un fichier absent de Drive ou abîmé n'est pas remis en place et est **signalé** à la fin. Une copie
  de sécurité de l'état actuel est faite juste avant le remplacement (elle reste dans *Sauvegarde et export*). Prévoyez le Wi‑Fi si vous avez
  beaucoup de photos.
- Une sauvegarde « données seules » de Drive ne se restaure **que** par ce chemin : si on la choisit dans *Sauvegarde et export*, un message
  l'explique et renvoie vers *Google Drive → Restaurer depuis Drive*. Les sauvegardes locales (archives complètes avec photos) ne changent pas.
- **Jamais de suppression, jamais de partage tout seul** (comme en partie 1) : droit `drive.file` seulement. Aucun changement de la base (schéma 6).

### Google Drive, partie 3 (étape 8 de l'évolution)

Deux choses : **donner le catalogue** à quelqu'un, et **partager un fichier de votre Drive** avec une personne précise (ou par un lien).

- **Exporter le catalogue** (*Réglages → Sauvegarde et export → Exporter le catalogue (produits et photos)*) : un fichier `.zip` avec le
  **tableau des produits** (`catalogue.csv`, à ouvrir avec Excel, LibreOffice ou Numbers : prix de vente en euros), les **mêmes informations en
  JSON** (`catalogue.json`), les **photos** (`photos/PRD-0001_1.jpg`…) et un petit mode d'emploi (`LISEZMOI.txt`). Il se partage par la feuille
  de partage d'Android (e-mail, messagerie, Drive…). **Il ne contient jamais** les coûts des matières, les stocks, les clients, les ventes ni
  les factures : c'est fait pour être donné. Les produits archivés n'y sont pas ; une photo introuvable sur le téléphone est **signalée** (un
  message, et le `LISEZMOI.txt`), jamais inventée. Ce n'est **pas une sauvegarde** : il ne se restaure pas.
- **Partager des fichiers** (*Réglages → Google Drive → Partager des fichiers…*, après connexion à Google) : l'écran **Partages** liste vos
  **factures**, vos **devis** et vos **exports** déjà sur Drive, avec « Partagé » ou « Privé ». Les fichiers doivent d'abord être envoyés sur
  Drive (écran *Google Drive*, « Envoyer sur Drive »). **Vos sauvegardes ne sont jamais proposées**, ni les photos des produits ni les pièces
  jointes des notes.
- **Envoyer le catalogue sur Drive** (écran Partages) : prépare le même `.zip` et l'envoie dans le dossier **« Exports »** de votre Drive. Le
  renvoyer le même jour met à jour le même fichier (ceux qui y ont accès voient la nouvelle version ; Drive garde l'ancienne dans
  l'historique du fichier). Il apparaît ensuite dans la rubrique **Exports**, prêt à être partagé.
- **Un fichier, un écran** (toucher un fichier de la liste) :
  - **Qui a accès** : vous (propriétaire), les personnes avec qui il est partagé, le lien public s'il est activé. Un accès créé en dehors de
    l'application (un groupe, ou le droit de modifier donné à la main dans Drive) est **montré, jamais modifié** : à gérer dans Drive.
  - **Partager avec une personne** : saisissez son adresse e-mail. Elle peut **lire** le fichier, **sans pouvoir le modifier**, et Google la
    prévient par e-mail. L'adresse est vérifiée avant tout (vide, mal écrite, la vôtre, déjà partagée). Si Google la refuse (par exemple une
    adresse sans compte Google, selon les réglages de votre Drive), le message le dit et rien n'est partagé.
  - **Retirer l'accès** d'une personne : confirmation, puis elle ne peut plus ouvrir le fichier. **Le fichier reste sur votre Drive.**
  - **Lien** : **Copier le lien** donne l'adresse du fichier (seules les personnes ayant accès peuvent l'ouvrir). **Activer le lien public…**
    permet à **toute personne qui a le lien** de lire le fichier, même sans compte Google (sans pouvoir le modifier, et sans qu'il apparaisse
    dans une recherche) : une **confirmation** l'explique d'abord, et rappelle qu'une facture ou un devis contient le nom et l'adresse du
    client. **Arrêter le lien public…** (avec confirmation) le retire ; les personnes avec qui le fichier est partagé gardent leur accès.
- **Rien n'est partagé sans votre geste** : ni à l'envoi, ni à la sauvegarde, ni à la connexion. **Un partage ne donne que le droit de lire.**
  **L'application ne supprime jamais un fichier sur Drive** : arrêter un partage retire un accès, pas le fichier. Droit demandé à Google inchangé :
  `drive.file` (seuls les fichiers créés par l'application ; le reste de votre Drive reste invisible pour elle).
- Aucun changement de la base (schéma 6) ni de la sauvegarde ; aucune nouvelle dépendance.

### Ce que contient l'étape 11 : sauvegarde et export

- **Écran « Sauvegarde et export »** (écran 23, *Plus → Réglages → Sauvegarde et export*) : sauvegarder, partager, restaurer
  et exporter, au même endroit.
- **Une sauvegarde = un fichier `.zip`** qui contient **toutes les données** (produits, clients, ventes, factures, devis,
  cours, inscriptions, dépenses, réglages, compteurs de numéros) **et les fichiers** : photos des produits et des tickets,
  PDF des factures et des devis. Elle est rangée sur le téléphone, avec sa date et son heure.
- **Une sauvegarde fiable** (étape 3 du plan d'évolution) : elle est **écrite fichier après fichier** (jamais entièrement en
  mémoire), avec la **liste des fichiers, leur taille et leur empreinte SHA-256**, puis **relue** avant d'être rangée. Elle est
  **incomplète** si une **photo** citée par les données manque sur le téléphone : son nom se termine alors par `-incomplete` et la
  liste l'indique. L'application **contrôle la place libre** avant d'écrire et affiche une **progression** (étape, fichiers faits).
  À la restauration, **chaque fichier est contrôlé avant de toucher à quoi que ce soit** : une archive abîmée est refusée.
- **Sauvegarde automatique** : à l'ouverture de l'application, si la dernière sauvegarde date d'**un jour ou plus**, une
  nouvelle est faite en arrière-plan, sans rien demander. Les **7 dernières** sont conservées ; les plus anciennes sont
  supprimées.
- **Sauvegarder maintenant** (sauvegarde manuelle) : conservée jusqu'à ce qu'on la supprime. Le menu ⋮ de chaque sauvegarde
  permet de la **partager** (e-mail, messagerie, Drive… pour en garder une copie *hors* du téléphone), de la **restaurer** ou
  de la **supprimer**.
- **Restaurer** (depuis la liste, ou **depuis un fichier** `.zip` choisi dans le téléphone, par exemple reçu par e-mail) :
  l'application vérifie d'abord que c'est bien une sauvegarde de l'application, dit ce qu'elle contient et demande
  confirmation (en avertissant si la sauvegarde est **incomplète**). La restauration **remplace tout** (données, photos, PDF).
  Juste avant de remplacer, une **copie de sécurité** de l'état actuel est faite (les 3 dernières sont conservées, dans la même
  liste). Si la restauration échoue en route, **rien n'est modifié**. Les sauvegardes faites avec les versions précédentes se
  restaurent toujours (leurs fichiers ne peuvent simplement pas être contrôlés par empreinte).
- **Export CSV** : un `.zip` avec **un tableau par type** — produits, clients, ventes, factures, devis, cours,
  inscriptions, dépenses — à ouvrir dans Excel ou LibreOffice (séparateur point-virgule, montants en euros `12,50`, dates
  `05/03/2026`, accents corrects). Un CSV sert à lire ou à calculer, **pas à restaurer** : pour cela, il faut une sauvegarde.
- **Export JSON** : toutes les données dans un seul fichier, sans photos ni PDF (pour un usage technique).
- Tout se fait **sans connexion** : aucun service en ligne. Pour une vraie sécurité, partagez de temps en temps une
  sauvegarde hors du téléphone : si le téléphone est perdu, les sauvegardes qu'il contient le sont aussi. (Une copie de vos **données** peut aussi partir sur Google Drive,
  à la demande ou une fois par jour : voir « Google Drive, partie 2 ».)

### Ce que contient l'étape 10 : statistiques

- **Écran Statistiques** (écran 20, *Plus → Statistiques*, ou un appui sur « Ventes du mois » / « Cours du mois » de
  l'accueil) : un sélecteur **Jour / Semaine / Mois / Année** choisit la période **en cours** (la semaine va du lundi au
  dimanche). Les chiffres se mettent à jour tout seuls dès qu'une vente, un paiement, une dépense ou une facture change.
- **Chiffre d'affaires = argent encaissé** : un paiement compte à la date où il est reçu, un remboursement se déduit à la
  date où il est fait. Il est séparé en **objets** (frais de port compris) et **cours et prestations** (avec la part des
  **cours** à part, aussi affichée dans « Revenus des cours »). Un acompte compte pour sa part de chaque ligne de la
  vente ; une remise est répartie au prorata des lignes.
- **Marge estimée** = argent encaissé − **coût de la matière** des articles correspondants (le coût relevé au catalogue au
  moment de la vente). Les cours et prestations n'ont pas de coût de matière. Les **dépenses ne sont pas déduites** de la
  marge : elles sont présentées à part, **par catégorie**, avec leur total.
- **Panier moyen** (total moyen des ventes validées faites sur la période), **meilleures ventes** (les 5 articles les plus
  vendus, hors cours), **catégories les plus rentables** (marge par catégorie de produit), **stock faible**
  (produits à réapprovisionner) et **factures impayées** (nombre et reste à encaisser ; un appui ouvre la liste des factures).
- **Franchise de TVA** (écran Statistiques et accueil) : l'argent encaissé **depuis le 1er janvier** face aux seuils de
  **85 000 €** (objets) et **37 500 €** (cours et prestations). Dès **80 %** d'un seuil, la barre change de couleur
  avec l'étiquette « Seuil approché » et un message ; au-delà du seuil, elle devient rouge avec « Seuil dépassé ».
  L'application ne remplace pas un comptable : en cas d'alerte, elle invite à en parler à son comptable ou au service
  des impôts.
- **Accueil** : « Ventes du mois » (argent encaissé ce mois-ci, hors cours), « Cours du mois », « Factures impayées »
  (nombre et reste à encaisser) et la carte de franchise sont désormais branchés.

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
- Les totaux **par catégorie** et la marge estimée sont dans les statistiques (étape 10).

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
- **Le PDF** : fond blanc (même en mode nuit), bande rose et verte, logo de l'entreprise, vos coordonnées, celles du
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

### Signature de l'application (mises à jour sans perte de données)

Android n'installe une nouvelle version **par-dessus** l'ancienne que si les deux sont signées avec la **même clé**. La CI
signe l'APK avec une clé stable conservée dans les « secrets » du dépôt ; la clé elle-même n'est **jamais** dans le dépôt
(`*.p12` est ignoré par git). Sans ces secrets, la CI reste fonctionnelle mais signe avec une clé de débogage différente à
chaque construction (avertissement dans le journal).

**Mise en place, une seule fois** : sur GitHub, dépôt › **Settings › Secrets and variables › Actions › New repository secret**,
créer deux secrets :

| Nom du secret | Contenu |
|---------------|---------|
| `ANDROID_KEYSTORE_BASE64` | la clé de signature (fichier `.p12`) encodée en texte base64 |
| `ANDROID_KEYSTORE_PASSWORD` | le mot de passe de la clé (l'alias, `crochet-creations`, est écrit dans le workflow) |

Un collage fait depuis un téléphone embarque facilement des retours à la ligne ou du texte en trop : la CI les ignore (et le signale
par un avertissement) ; si la clé est vraiment incomplète ou le mot de passe faux, le journal indique les longueurs reçues.

**Vérification** : dans les notes de la pré-version et dans le résumé de l'exécution (onglet *Actions*), l'empreinte du
certificat est affichée, avec le verdict « Conforme à l'empreinte attendue ». Cette empreinte SHA-256 est aussi enregistrée dans
`tool/signature_attendue.txt` : si elle diffère, la construction est marquée en échec. L'empreinte **SHA-1** affichée est celle
que demandera Google Cloud pour la connexion à Google Drive (voir « Configurer Google Cloud » plus haut).

**À conserver précieusement** : le fichier `.p12` et son mot de passe (gestionnaire de mots de passe, clé USB). GitHub ne
permet pas de relire un secret. Perdre la clé n'est pas dramatique, mais oblige à en créer une nouvelle et donc à
désinstaller/réinstaller l'application une fois (faire alors une sauvegarde avant).

**Première installation après ce changement** : l'application déjà installée porte une autre signature, Android refusera de
l'écraser. Faire une sauvegarde (*Réglages › Sauvegarde et export*) et la partager hors du téléphone, désinstaller, installer
le nouvel APK, puis restaurer. Ensuite, chaque APK s'installe par-dessus le précédent.

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

### Version Windows (dossier .zip portable)

La même application, construite pour Windows 10/11 par GitHub, **sans rien installer** :

1. Sur GitHub, dépôt › **Releases** (https://github.com/Stephane1972/crochet-creations/releases) › ouvrir la pré-version
   **« Windows (dossier .zip portable) — … »** de la branche voulue et télécharger `crochet-creations-windows-XXXXXXX.zip`.
2. Clic droit sur le .zip › **Extraire tout…**, puis ouvrir le dossier obtenu et double-cliquer sur **`crochet_creations.exe`**
   (le fichier `LISEZMOI.txt` du dossier explique la suite). Windows peut afficher « Windows a protégé votre ordinateur » : le
   programme n'est pas signé par un éditeur payant ; *Informations complémentaires › Exécuter quand même*.
3. Les données restent sur l'ordinateur (dossier `%APPDATA%\fr.crochetcreations`) ; rien n'est envoyé sur Internet, sauf si vous
   connectez Google Drive (voir ci-dessous).

**Ce qui est pareil** : tous les écrans, les calculs, les factures et devis en PDF, les statistiques, la sauvegarde et la restauration.
La fenêtre se redimensionne ; le contenu garde la largeur d'un grand téléphone, centré.

**Ce qui change** (et pourquoi) :

| Sur Android | Sous Windows |
|-------------|--------------|
| Google Drive : connexion par Google Play Services, avec l'**ID client Web** | Google Drive : connexion **dans le navigateur**, avec un accès « **application de bureau** » (ID client + code secret) — voir « Google Drive sous Windows » |
| Appareil photo, caméra | on **choisit un fichier** déjà sur l'ordinateur |
| Feuille de partage d'Android | **« Enregistrer sous… »** (fenêtre Windows de choix d'emplacement) |
| Photos réduites à l'ajout | photos **gardées à leur taille d'origine** (le sélecteur Windows ne sait pas les réduire) |

**Passer ses données du téléphone au PC (ou l'inverse)**, de deux façons : par **Google Drive** (voir ci-dessous), ou sans Drive : *Réglages › Sauvegarde et export › Sauvegarder maintenant*, enregistrer
le `.zip` (Android : « Partager » ; Windows : « Enregistrer sous… »), le faire passer à l'autre appareil (e-mail, clé USB…),
puis *Restaurer une sauvegarde* sur l'autre appareil.

#### Google Drive sous Windows (version 0.24.0)

Même Drive, mêmes dossiers, mêmes sauvegardes que sur le téléphone : l'écran *Réglages › Google Drive* de Windows envoie les fichiers,
sauvegarde les données et restaure comme sur Android. Seule la **connexion** diffère : Google Play Services n'existe pas sur Windows, la
connexion se fait donc **dans votre navigateur** (méthode que Google prévoit pour les applications installées).

**Configuration unique, gratuite (≈ 5 minutes)** — dans le **même projet Google Cloud** que pour le téléphone (voir « Configurer Google
Cloud » plus haut) :

1. Console Google Cloud → **API et services → Identifiants** (ou *Google Auth Platform → Clients*) → **Créer un client** → type
   d'application **Application de bureau** (*Desktop app*) → nom « Windows » → **Créer**.
2. Google affiche l'**ID client** (il se termine par `.apps.googleusercontent.com`) et le **code secret du client** (il commence par
   `GOCSPX-`). Pour une application installée, Google considère ce code comme non confidentiel, mais **ne le publiez nulle part** (ni GitHub,
   ni message public) : il n'est pas dans le code du projet.
3. Vérifiez que l'application est **publiée** (*Audience → Publier l'application*) : tant qu'elle est en « test », Google coupe
   l'autorisation tous les **7 jours** (il faut alors simplement se reconnecter).
4. Dans la version Windows : *Réglages → Google Drive → carte « Accès Google “application de bureau” »* → coller l'ID et le code secret →
   **Enregistrer**, puis **Se connecter à Google** : le navigateur s'ouvre, connectez-vous, **laissez la case Drive cochée**, puis revenez à
   l'application.

- **Où c'est gardé** : l'ID, le code secret et l'autorisation durable sont dans un petit fichier du dossier de données de l'utilisateur
  (`…\fr.crochetcreations\…\drive\google_bureau.json`). Ce fichier n'est ni dans la base ni dans les sauvegardes. *Se déconnecter* oublie
  l'autorisation et la fait retirer chez Google ; *Oublier l'accès enregistré* efface aussi l'ID et le code secret.
- **Droit demandé** : toujours **`drive.file`** (seuls les fichiers créés par l'application) pour Drive, plus l'identité (adresse e-mail et nom,
  pour afficher « Connecté en tant que… »). L'application ne supprime rien sur Drive.
- **Pas de connexion tant que l'accès n'est pas saisi** : l'application fonctionne normalement sans Drive.
- **Si la connexion échoue** : l'écran affiche la raison. Causes habituelles : accès créé avec un autre type que « Application de bureau »,
  ID et code secret qui viennent de deux accès différents, case Drive décochée dans la fenêtre de Google, API Google Drive non activée,
  application non publiée et adresse absente des utilisateurs test, pare-feu ou antivirus qui bloque l'écoute locale pendant la connexion.

La construction est faite par le workflow `.github/workflows/windows.yml`, **indépendant** de celui d'Android : à chaque envoi, il
construit l'application, la **démarre pour de vrai** sur un serveur Windows (`integration_test/demarrage_windows_test.dart`) puis
publie le `.zip`. Le workflow Android (analyse, tests, APK signé) n'a pas changé.

Pour construire à la main sur un PC Windows (avec Flutter) : `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
`bash tool/setup_windows.sh` (Git Bash), puis `flutter run -d windows` ou `flutter build windows --release`.

#### Synchroniser le téléphone et le PC (version 0.25.0)

Pour retrouver les **mêmes données** sur le téléphone Android et sur le PC Windows, en passant par votre Drive. Le principe : **un seul
appareil est utilisé à la fois**. Quand vous le quittez, ses données partent sur Drive ; quand vous ouvrez l'autre, il vous propose de les
reprendre. **Il n'y a pas de fusion** : si les deux appareils ont changé chacun de leur côté, c'est vous qui choisissez, et rien n'est jamais
écrasé en silence.

**À faire une fois, sur chaque appareil** : *Réglages → Google Drive* → se connecter au **même compte Google**, puis activer
**« Envoi automatique et reprise entre appareils »** (désactivé au départ).

**Ce qui se passe ensuite** (envoi automatique activé et Google connecté) :

- **Quand vous quittez un appareil** : sous **Windows**, à la fermeture de la fenêtre, ce qui a changé part sur Drive (un message s'affiche si
  cela dure plus d'un instant, avec un bouton **« Fermer sans attendre »** : l'envoi est alors refait à la prochaine ouverture) ; sous
  **Android**, quand vous quittez l'application (retour à l'écran d'accueil du téléphone), l'envoi part en arrière-plan, **au plus toutes
  les 10 minutes**. Rien ne part si rien n'a changé.
- **Quand vous ouvrez l'autre appareil** : l'application compare avec Drive. Si Drive a une **version plus récente, envoyée depuis l'autre
  appareil**, une fenêtre vous le dit.
  - Si **rien n'a changé** sur cet appareil depuis la dernière synchronisation : **Reprendre** ouvre l'écran de restauration avec cette
    version déjà choisie (téléchargement, résumé de ce qu'elle contient, **demande de confirmation**, copie de sécurité faite avant de
    remplacer).
  - Si cet appareil **a aussi changé** : **Deux versions différentes**. *Reprendre la version de Drive* remplace les données de cet appareil
    (après confirmation et copie de sécurité) ; *Garder cet appareil* laisse la version de Drive sur Drive, sans la reprendre : le prochain
    envoi ajoutera celle de cet appareil comme version la plus récente, et l'autre reste restaurable depuis *Google Drive → Restaurer*.
  - **Plus tard** ne change rien : la proposition reste affichée en haut de l'écran *Google Drive* (bouton **Décider**).
  - **Tant que vous n'avez pas choisi, rien n'est envoyé automatiquement** (ni à l'ouverture, ni en arrière-plan, ni à la fermeture).
- **Rien n'est jamais supprimé sur Drive** : chaque envoi ajoute une sauvegarde datée (toutes restent restaurables). Comptez donc **une
  sauvegarde de plus à chaque fermeture où quelque chose a changé** ; vous pouvez les supprimer vous-même dans Drive.

**Comment l'application sait ce qui a changé** : chaque appareil retient la dernière version de Drive qu'il a envoyée ou reprise, et une
empreinte de ses données à ce moment-là. En comparant cette empreinte à ses données du moment, il sait s'il a changé, **sans accès au
réseau**. Les photos et documents ne comptent pas dans cette comparaison (chacun est cité par une ligne des données). Aucun changement de la
base ni du format des sauvegardes (schéma 6).

**Limites** (à connaître) :

- **Pas de fusion** de modifications faites en même temps sur les deux appareils : on garde l'une ou l'autre.
- Les deux appareils utilisés **en même temps** laissent une petite fenêtre où une version peut en dépasser une autre avant que l'écran ne
  le propose ; l'ancienne version reste sur Drive et restaurable.
- Sous **Android**, l'envoi en arrière-plan est **fait au mieux** : le système peut l'interrompre (économie d'énergie, application fermée de
  force). Dans ce cas, il est refait à la prochaine ouverture. Sous **Windows**, un arrêt brutal (extinction, fermeture forcée) ne laisse pas
  le temps d'envoyer.
- Le bouton manuel *Sauvegarder maintenant sur Drive* n'est pas bloqué par la proposition en attente : l'utiliser pendant « Deux versions
  différentes » ajoute simplement une version plus récente (rien n'est écrasé, tout reste restaurable).
- Un devis qui **expire tout seul** modifie les données : il compte comme un changement et déclenche un envoi.
- Cette fonction n'a pas pu être essayée avec un vrai compte Google pendant le développement : elle est vérifiée par des tests automatiques
  (faux Google, deux appareils simulés). Le premier essai réel, téléphone et PC ensemble, est le vrai test.

## Structure du dépôt

```
lib/            code de l'application : presentation, domain, data (voir ARCHITECTURE.md)
assets/         logo, icônes, police Poppins
test/           tests automatiques
integration_test/  test de démarrage de la vraie application sous Windows (lancé par la CI Windows)
tool/           scripts : génération des icônes et des dossiers android/ et windows/, signature de l'APK, annotations de la CI
.github/        constructions automatiques : APK Android (android.yml) et dossier .zip Windows (windows.yml)
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
