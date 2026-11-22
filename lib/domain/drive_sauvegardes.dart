// Google Drive, partie 2 (étape 7 de l'évolution) : les sauvegardes des données sur Drive.
//
// Des règles pures, testées sans réseau ni téléphone. Une sauvegarde Drive est un petit fichier « données seules » : les
// données (toutes les tables) et la liste des fichiers avec leur empreinte. Les photos, factures, devis et pièces jointes
// sont déjà dans leurs dossiers Drive (étape 6) : on ne les copie pas une seconde fois. Rien n'est jamais supprimé.

import 'drive_envoi.dart';

/// Nom du sous-dossier des sauvegardes, sous le dossier principal « Un p'tit crochet dans les stocks ».
const String nomDossierSauvegardesDrive = 'Sauvegardes';

/// `crochet-creations-sauvegarde-2026-11-14-183005.zip` : le nom d'une sauvegarde Drive faite à cet instant.
String nomSauvegardeDrive(DateTime date) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return 'crochet-creations-sauvegarde-${date.year.toString().padLeft(4, '0')}-${deux(date.month)}-${deux(date.day)}-'
      '${deux(date.hour)}${deux(date.minute)}${deux(date.second)}.zip';
}

final RegExp _modeleNomSauvegardeDrive = RegExp(
  r'^crochet-creations-sauvegarde-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})\.zip$',
);

/// La date écrite dans le nom d'une sauvegarde Drive ; `null` si ce n'est pas un nom de sauvegarde (ou une date impossible).
DateTime? dateDeNomSauvegardeDrive(String nom) {
  final RegExpMatch? m = _modeleNomSauvegardeDrive.firstMatch(nom);
  if (m == null) return null;
  final List<int> n = <int>[for (int i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final DateTime date = DateTime(n[0], n[1], n[2], n[3], n[4], n[5]);
  // « 2026-13-45 » ne donne pas une date : DateTime la ramène au mois suivant, on la refuse.
  final bool identique =
      date.year == n[0] && date.month == n[1] && date.day == n[2] && date.hour == n[3] && date.minute == n[4] && date.second == n[5];
  return identique ? date : null;
}

/// Une sauvegarde trouvée sur Drive.
class SauvegardeDrive {
  const SauvegardeDrive({required this.id, required this.nom, required this.date, this.octets, this.empreinte});

  final String id;
  final String nom;

  /// Date et heure de la sauvegarde, lues dans le nom du fichier.
  final DateTime date;

  /// Taille du fichier (inconnue : `null`).
  final int? octets;

  /// Empreinte des données (voir `DonneesSeules.empreinte`) notée à l'envoi : sert à reconnaître qu'il n'y a rien de neuf.
  final String? empreinte;
}

/// Les sauvegardes parmi les [fichiers] d'un dossier Drive, de la plus récente à la plus ancienne. Les fichiers qui n'ont pas
/// un nom de sauvegarde (déposés à la main, par exemple) sont ignorés.
List<SauvegardeDrive> sauvegardesDrive(List<FichierDistant> fichiers) {
  final List<SauvegardeDrive> liste = <SauvegardeDrive>[
    for (final FichierDistant f in fichiers)
      if (dateDeNomSauvegardeDrive(f.nom) case final DateTime date)
        SauvegardeDrive(id: f.id, nom: f.nom, date: date, octets: f.octets, empreinte: f.empreinte),
  ];
  liste.sort((SauvegardeDrive a, SauvegardeDrive b) {
    final int parDate = b.date.compareTo(a.date);
    return parDate != 0 ? parDate : b.nom.compareTo(a.nom);
  });
  return liste;
}

/// Une sauvegarde faite par l'application (ce qu'on en retient sur le téléphone).
class BilanSauvegardeDrive {
  const BilanSauvegardeDrive({required this.date, required this.nom, this.octets, this.fichiers});

  final DateTime date;
  final String nom;
  final int? octets;

  /// Nombre de fichiers (photos, factures...) listés dans la sauvegarde ; `null` si on ne le sait pas (sauvegarde faite
  /// avant une réinstallation, par exemple).
  final int? fichiers;

  Map<String, Object?> versJson() => <String, Object?>{
    'date': date.toIso8601String(),
    'nom': nom,
    'octets': octets,
    'fichiers': fichiers,
  };

  static BilanSauvegardeDrive? depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? date = json['date'];
    final Object? nom = json['nom'];
    final Object? octets = json['octets'];
    final Object? fichiers = json['fichiers'];
    if (date is! String || nom is! String) return null;
    final DateTime? quand = DateTime.tryParse(date);
    if (quand == null) return null;
    return BilanSauvegardeDrive(date: quand, nom: nom, octets: octets is int ? octets : null, fichiers: fichiers is int ? fichiers : null);
  }
}

/// La dernière version des données sur Drive que **cet appareil** a envoyée ou reprise : c'est à partir d'elle qu'il sait si
/// Drive a du plus récent (envoyé depuis un autre appareil) et s'il a lui-même changé depuis (voir `drive_synchro.dart`).
class ReferenceSynchro {
  const ReferenceSynchro({required this.nom, required this.date, this.empreinteLocale});

  /// Nom de la sauvegarde sur Drive (`crochet-creations-sauvegarde-…zip`).
  final String nom;

  /// Date de cette sauvegarde, lue dans son nom.
  final DateTime date;

  /// Empreinte des données de cet appareil au moment où elles étaient identiques à cette sauvegarde (voir
  /// `ServiceSauvegarde.empreinteLocale`) ; `null` si on ne la connaît pas (état d'avant la synchronisation).
  final String? empreinteLocale;

  Map<String, Object?> versJson() => <String, Object?>{
    'nom': nom,
    'date': date.toIso8601String(),
    'empreinteLocale': empreinteLocale,
  };

  static ReferenceSynchro? depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? nom = json['nom'];
    final Object? date = json['date'];
    final Object? empreinte = json['empreinteLocale'];
    if (nom is! String || date is! String) return null;
    final DateTime? quand = DateTime.tryParse(date);
    if (quand == null) return null;
    return ReferenceSynchro(nom: nom, date: quand, empreinteLocale: empreinte is String ? empreinte : null);
  }
}

/// Ce que le téléphone retient des sauvegardes Drive : le réglage « envoi automatique », la dernière sauvegarde et le dernier
/// contrôle. Gardé dans un petit fichier, hors de la base et de la sauvegarde.
class EtatSauvegardesDrive {
  const EtatSauvegardesDrive({
    this.envoiAutomatique = false,
    this.derniereVerification,
    this.derniere,
    this.fichiersNonEnvoyes = const <String>[],
    this.reference,
  });

  /// L'envoi automatique est activé (désactivé au départ).
  final bool envoiAutomatique;

  /// Dernière fois qu'une sauvegarde est allée jusqu'au bout (envoyée, ou déjà à jour). Sert à ne rien refaire avant un jour.
  final DateTime? derniereVerification;

  /// La dernière sauvegarde envoyée sur Drive.
  final BilanSauvegardeDrive? derniere;

  /// Fichiers (`photos_produits/photo_1.jpg`) qui n'ont pas pu partir lors de la dernière sauvegarde : elle ne les liste pas.
  final List<String> fichiersNonEnvoyes;

  /// La dernière version de Drive que cet appareil a envoyée ou reprise (`null` : jamais, ou état d'avant la synchronisation).
  final ReferenceSynchro? reference;

  EtatSauvegardesDrive copier({
    bool? envoiAutomatique,
    DateTime? derniereVerification,
    BilanSauvegardeDrive? derniere,
    List<String>? fichiersNonEnvoyes,
    ReferenceSynchro? reference,
  }) => EtatSauvegardesDrive(
    envoiAutomatique: envoiAutomatique ?? this.envoiAutomatique,
    derniereVerification: derniereVerification ?? this.derniereVerification,
    derniere: derniere ?? this.derniere,
    fichiersNonEnvoyes: fichiersNonEnvoyes ?? this.fichiersNonEnvoyes,
    reference: reference ?? this.reference,
  );

  Map<String, Object?> versJson() => <String, Object?>{
    'envoiAutomatique': envoiAutomatique,
    'derniereVerification': derniereVerification?.toIso8601String(),
    'derniere': derniere?.versJson(),
    'fichiersNonEnvoyes': fichiersNonEnvoyes,
    'reference': reference?.versJson(),
  };

  /// Relit l'état enregistré. Un fichier illisible ou incomplet donne les valeurs de départ (envoi automatique désactivé) :
  /// jamais une erreur.
  static EtatSauvegardesDrive depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return const EtatSauvegardesDrive();
    final Object? automatique = json['envoiAutomatique'];
    final Object? verification = json['derniereVerification'];
    final Object? nonEnvoyes = json['fichiersNonEnvoyes'];
    return EtatSauvegardesDrive(
      envoiAutomatique: automatique == true,
      derniereVerification: verification is String ? DateTime.tryParse(verification) : null,
      derniere: BilanSauvegardeDrive.depuisJson(json['derniere']),
      fichiersNonEnvoyes: nonEnvoyes is List<Object?> ? <String>[for (final Object? n in nonEnvoyes) if (n is String) n] : const <String>[],
      reference: ReferenceSynchro.depuisJson(json['reference']),
    );
  }
}

/// L'envoi automatique doit-il passer maintenant ? Oui s'il est activé et que le dernier passage réussi date d'un jour ou plus
/// (ou n'a jamais eu lieu). Une horloge revenue en arrière (dernier passage « dans le futur ») ne bloque pas.
bool envoiAutomatiqueDu(EtatSauvegardesDrive etat, DateTime maintenant, {Duration delai = const Duration(days: 1)}) {
  if (!etat.envoiAutomatique) return false;
  final DateTime? derniere = etat.derniereVerification;
  if (derniere == null) return true;
  final Duration ecoule = maintenant.difference(derniere);
  return ecoule.isNegative || ecoule >= delai;
}
