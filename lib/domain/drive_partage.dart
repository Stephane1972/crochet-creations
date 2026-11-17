// Google Drive, partie 3 (étape 8 de l'évolution) : partager un fichier de Drive avec une personne, ou par un lien.
//
// Des règles pures, testées sans réseau ni téléphone. Les principes :
// - **rien n'est partagé sans un geste de la personne** : ni lien public ni adresse ajoutée par l'application toute seule ;
// - un partage donne seulement le droit de **lire** (jamais de modifier) ;
// - seuls les factures, les devis et les exports sont partageables : **jamais les sauvegardes** (elles contiennent toutes les
//   données), ni les photos et pièces jointes des notes ;
// - arrêter un partage retire un accès ; **le fichier lui-même n'est jamais supprimé**.

import 'regles_client.dart';

/// Nom du dossier Drive où l'application range ses exports (catalogue), sous le dossier principal.
const String nomDossierExportsDrive = 'Exports';

/// Les rubriques de fichiers que l'on peut partager.
enum RubriquePartage {
  factures('Factures', 'Factures', 'Les PDF des factures déjà envoyés sur Drive.'),
  devis('Devis', 'Devis', 'Les PDF des devis déjà envoyés sur Drive.'),
  exports(nomDossierExportsDrive, 'Exports', 'Le catalogue des produits, envoyé depuis cet écran.');

  const RubriquePartage(this.nomDrive, this.titre, this.explication);

  /// Nom du sous-dossier dans Drive.
  final String nomDrive;

  /// Titre affiché.
  final String titre;

  /// Ce qu'on y trouve.
  final String explication;
}

/// Comment un fichier est accessible à quelqu'un.
enum TypeAcces {
  /// Le propriétaire du fichier : la personne elle-même (non retirable).
  proprietaire,

  /// Une personne précise, par son adresse e-mail.
  personne,

  /// Toute personne qui a le lien.
  lienPublic,

  /// Un autre type d'accès, créé hors de l'application (groupe, domaine) : montré, jamais modifié.
  autre,
}

/// D'après le « type » et le « rôle » d'un droit Drive (`user`/`anyone`/`group`/`domain`, `owner`/`reader`/`writer`…).
TypeAcces typeAccesDrive({required String? type, required String? role}) {
  if (role == 'owner') return TypeAcces.proprietaire;
  if (type == 'anyone') return TypeAcces.lienPublic;
  if (type == 'user') return TypeAcces.personne;
  return TypeAcces.autre;
}

/// Un accès à un fichier Drive.
class AccesDrive {
  const AccesDrive({required this.id, required this.type, this.email, this.nom, this.peutModifier = false});

  /// Identifiant du droit chez Google (pour le retirer).
  final String id;
  final TypeAcces type;
  final String? email;
  final String? nom;

  /// Vrai si cet accès permet aussi de modifier (créé hors de l'application) : à signaler.
  final bool peutModifier;

  /// Comment l'accès s'écrit : le nom puis l'adresse, ou l'adresse seule, ou « Toute personne ayant le lien ».
  String get libelle {
    switch (type) {
      case TypeAcces.lienPublic:
        return 'Toute personne ayant le lien';
      case TypeAcces.proprietaire:
      case TypeAcces.personne:
      case TypeAcces.autre:
        final String adresse = (email ?? '').trim();
        final String quiEst = (nom ?? '').trim();
        if (quiEst.isNotEmpty && adresse.isNotEmpty && quiEst != adresse) return '$quiEst ($adresse)';
        if (adresse.isNotEmpty) return adresse;
        if (quiEst.isNotEmpty) return quiEst;
        return type == TypeAcces.autre ? 'Autre accès' : 'Propriétaire';
    }
  }
}

/// Tous les accès d'un fichier.
class AccesFichier {
  const AccesFichier(this.acces);

  final List<AccesDrive> acces;

  AccesDrive? get proprietaire {
    for (final AccesDrive a in acces) {
      if (a.type == TypeAcces.proprietaire) return a;
    }
    return null;
  }

  /// Les personnes avec qui le fichier est partagé (sans le propriétaire).
  List<AccesDrive> get personnes => <AccesDrive>[
    for (final AccesDrive a in acces)
      if (a.type == TypeAcces.personne) a,
  ];

  /// Le lien public (`null` : le lien n'est pas public).
  AccesDrive? get lienPublic {
    for (final AccesDrive a in acces) {
      if (a.type == TypeAcces.lienPublic) return a;
    }
    return null;
  }

  List<AccesDrive> get autres => <AccesDrive>[
    for (final AccesDrive a in acces)
      if (a.type == TypeAcces.autre) a,
  ];

  /// Vrai si personne d'autre que le propriétaire n'y a accès.
  bool get estPrive => personnes.isEmpty && lienPublic == null && autres.isEmpty;

  /// Une phrase pour la liste : « Privé », « Partagé avec 2 personnes », « Lien public », etc.
  String get resume {
    if (estPrive) return 'Privé : vous seul·e y avez accès.';
    final List<String> morceaux = <String>[];
    final int n = personnes.length;
    if (n > 0) morceaux.add('partagé avec $n ${n > 1 ? 'personnes' : 'personne'}');
    if (lienPublic != null) morceaux.add('lien public activé');
    if (autres.isNotEmpty) morceaux.add('autres accès');
    final String phrase = morceaux.join(', ');
    return '${phrase[0].toUpperCase()}${phrase.substring(1)}.';
  }
}

/// L'adresse telle qu'on l'envoie à Google : sans espaces, en minuscules.
String normaliserCourriel(String saisie) => saisie.trim().toLowerCase();

/// Pourquoi cette adresse ne peut pas recevoir un partage (`null` : elle convient).
///
/// [emailProprietaire] : l'adresse du compte Google connecté (partager avec soi-même n'a pas de sens). [dejaPartagees] :
/// les adresses qui ont déjà accès.
String? erreurCourrielPartage(
  String saisie, {
  String? emailProprietaire,
  Iterable<String> dejaPartagees = const <String>[],
}) {
  final String adresse = normaliserCourriel(saisie);
  if (adresse.isEmpty) return 'Saisissez l’adresse e-mail de la personne.';
  final String? forme = verifierEmail(adresse);
  if (forme != null) return forme;
  if (emailProprietaire != null && normaliserCourriel(emailProprietaire) == adresse) {
    return 'C’est votre propre adresse : ce fichier est déjà à vous.';
  }
  for (final String deja in dejaPartagees) {
    if (normaliserCourriel(deja) == adresse) return 'Ce fichier est déjà partagé avec cette adresse.';
  }
  return null;
}
