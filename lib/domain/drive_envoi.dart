// Google Drive, partie 1 (étape 6 de l'évolution) : quels fichiers du téléphone partent vers Drive.
//
// Des règles pures, testées sans réseau ni téléphone. L'envoi ne fait que **copier** : rien n'est jamais supprimé ni rendu
// public sur Drive. Drive est la mémoire de ce qui est déjà parti : on compare les fichiers du téléphone à ceux du dossier
// Drive (nom, taille et, pour les PDF, empreinte), sans aucune table de suivi sur le téléphone.

/// Nom du dossier principal créé dans « Mon Drive ».
const String nomDossierRacineDrive = 'Un p’tit crochet dans les stocks';

/// Le droit demandé à Google : voir et gérer **seulement les fichiers créés par l'application**, jamais le reste du Drive.
const String porteeDrive = 'https://www.googleapis.com/auth/drive.file';

/// Propriété ajoutée à chaque fichier envoyé : son empreinte SHA-256, pour reconnaître un PDF modifié.
const String proprieteEmpreinteDrive = 'sha256';

/// Les quatre dossiers de fichiers de l'application qui partent vers Drive (les sauvegardes viendront à l'étape suivante).
enum DossierDrive {
  photos('photos_produits', 'Photos des produits', false),
  factures('factures', 'Factures', true),
  devis('devis', 'Devis', true),
  notes('notes_pieces_jointes', 'Notes - pièces jointes', false);

  const DossierDrive(this.nomLocal, this.nomDrive, this.compareContenu);

  /// Nom du dossier dans l'espace privé de l'application (le même que dans l'archive de sauvegarde).
  final String nomLocal;

  /// Nom du sous-dossier dans Drive.
  final String nomDrive;

  /// Vrai si un fichier de même nom et de même taille peut avoir changé (un PDF régénéré) : on compare alors l'empreinte.
  /// Les photos et les pièces jointes ne sont jamais modifiées après leur ajout (leur nom est unique) : nom et taille suffisent,
  /// ce qui évite de relire des vidéos de 150 Mo à chaque vérification.
  final bool compareContenu;
}

/// Un fichier du téléphone.
class FichierLocal {
  const FichierLocal({required this.nom, required this.octets, this.empreinte});

  final String nom;
  final int octets;

  /// SHA-256 (hexadécimal). Renseignée seulement pour les dossiers qui comparent le contenu.
  final String? empreinte;
}

/// Un fichier déjà présent dans le dossier Drive.
class FichierDistant {
  const FichierDistant({required this.id, required this.nom, this.octets, this.empreinte});

  final String id;
  final String nom;

  /// Taille (inconnue : `null`).
  final int? octets;

  /// SHA-256 notée à l'envoi (absente si le fichier n'a pas été envoyé par l'application).
  final String? empreinte;
}

enum ActionEnvoi {
  /// Le fichier n'existe pas encore sur Drive.
  creer,

  /// Le fichier existe sur Drive mais n'est plus le même : le nouveau contenu remplace l'ancien (Drive garde l'ancienne
  /// version dans l'historique du fichier).
  mettreAJour,
}

/// Un envoi à faire.
class EnvoiPrevu {
  const EnvoiPrevu({required this.fichier, required this.action, this.idDistant});

  final FichierLocal fichier;
  final ActionEnvoi action;

  /// Identifiant du fichier Drive à remplacer (pour [ActionEnvoi.mettreAJour]).
  final String? idDistant;
}

/// Ce qu'il y a à faire pour un dossier.
class PlanDossier {
  const PlanDossier({
    required this.dossier,
    required this.nombreLocaux,
    required this.dejaSurDrive,
    required this.aEnvoyer,
  });

  final DossierDrive dossier;

  /// Nombre de fichiers du dossier sur le téléphone.
  final int nombreLocaux;

  /// Fichiers identiques déjà sur Drive : rien à faire.
  final int dejaSurDrive;

  final List<EnvoiPrevu> aEnvoyer;

  int get octetsAEnvoyer => aEnvoyer.fold(0, (int somme, EnvoiPrevu e) => somme + e.fichier.octets);
}

/// Compare les fichiers [locaux] du dossier à ceux de Drive ([distants]) et dit ce qu'il reste à envoyer, dans l'ordre des noms.
///
/// Un fichier local est **déjà sur Drive** s'il y en a un du même nom, de la même taille et, quand le dossier compare le
/// contenu, de la même empreinte ; **à mettre à jour** s'il y a un fichier du même nom mais différent ; **à créer** sinon.
/// Si Drive a plusieurs fichiers du même nom (jamais créé par l'application, mais possible à la main), un fichier identique
/// est préféré ; à défaut le premier est mis à jour. Les fichiers de Drive qui n'existent plus sur le téléphone sont ignorés :
/// on ne supprime jamais rien sur Drive.
PlanDossier planifierEnvoi({
  required DossierDrive dossier,
  required List<FichierLocal> locaux,
  required List<FichierDistant> distants,
}) {
  final Map<String, List<FichierDistant>> parNom = <String, List<FichierDistant>>{};
  for (final FichierDistant d in distants) {
    parNom.putIfAbsent(d.nom, () => <FichierDistant>[]).add(d);
  }

  bool identique(FichierLocal local, FichierDistant distant) {
    if (distant.octets != local.octets) return false;
    if (!dossier.compareContenu) return true;
    return local.empreinte != null && local.empreinte == distant.empreinte;
  }

  final List<FichierLocal> tries = List<FichierLocal>.of(locaux)..sort((FichierLocal a, FichierLocal b) => a.nom.compareTo(b.nom));
  int deja = 0;
  final List<EnvoiPrevu> aEnvoyer = <EnvoiPrevu>[];
  for (final FichierLocal local in tries) {
    final List<FichierDistant>? memeNom = parNom[local.nom];
    if (memeNom == null || memeNom.isEmpty) {
      aEnvoyer.add(EnvoiPrevu(fichier: local, action: ActionEnvoi.creer));
    } else if (memeNom.any((FichierDistant d) => identique(local, d))) {
      deja++;
    } else {
      aEnvoyer.add(EnvoiPrevu(fichier: local, action: ActionEnvoi.mettreAJour, idDistant: memeNom.first.id));
    }
  }
  return PlanDossier(dossier: dossier, nombreLocaux: locaux.length, dejaSurDrive: deja, aEnvoyer: aEnvoyer);
}

/// Un fichier qui n'a pas pu partir.
class ErreurEnvoi {
  const ErreurEnvoi({required this.dossier, required this.nom, required this.message});

  final DossierDrive dossier;
  final String nom;
  final String message;

  Map<String, Object?> versJson() => <String, Object?>{'dossier': dossier.name, 'nom': nom, 'message': message};

  /// Relit une erreur enregistrée ; `null` si elle est illisible (dossier inconnu, champ manquant).
  static ErreurEnvoi? depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? dossier = json['dossier'];
    final Object? nom = json['nom'];
    final Object? message = json['message'];
    if (dossier is! String || nom is! String || message is! String) return null;
    for (final DossierDrive d in DossierDrive.values) {
      if (d.name == dossier) return ErreurEnvoi(dossier: d, nom: nom, message: message);
    }
    return null;
  }
}

/// Le bilan d'un envoi : ce qui est parti, ce qui était déjà sur Drive, ce qui a échoué.
class RapportEnvoi {
  const RapportEnvoi({
    required this.date,
    this.envoyes = 0,
    this.dejaSurDrive = 0,
    this.octetsEnvoyes = 0,
    this.erreurs = const <ErreurEnvoi>[],
    this.interrompu = false,
  });

  final DateTime date;

  /// Fichiers envoyés (créés ou mis à jour).
  final int envoyes;

  final int dejaSurDrive;
  final int octetsEnvoyes;
  final List<ErreurEnvoi> erreurs;

  /// Vrai si l'envoi a été arrêté avant la fin (par la personne, ou parce que la connexion à Google a été perdue).
  final bool interrompu;

  /// Tout est sur Drive : aucune erreur et l'envoi est allé jusqu'au bout.
  bool get complet => erreurs.isEmpty && !interrompu;

  Map<String, Object?> versJson() => <String, Object?>{
    'date': date.toIso8601String(),
    'envoyes': envoyes,
    'dejaSurDrive': dejaSurDrive,
    'octetsEnvoyes': octetsEnvoyes,
    'interrompu': interrompu,
    'erreurs': <Object?>[for (final ErreurEnvoi e in erreurs) e.versJson()],
  };

  /// Relit un bilan enregistré ; `null` s'il est illisible.
  static RapportEnvoi? depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? date = json['date'];
    final Object? envoyes = json['envoyes'];
    final Object? deja = json['dejaSurDrive'];
    final Object? octets = json['octetsEnvoyes'];
    final Object? interrompu = json['interrompu'];
    final Object? erreurs = json['erreurs'];
    if (date is! String || envoyes is! int || deja is! int || octets is! int || interrompu is! bool || erreurs is! List<Object?>) {
      return null;
    }
    final DateTime? quand = DateTime.tryParse(date);
    if (quand == null) return null;
    return RapportEnvoi(
      date: quand,
      envoyes: envoyes,
      dejaSurDrive: deja,
      octetsEnvoyes: octets,
      interrompu: interrompu,
      erreurs: <ErreurEnvoi>[
        for (final Object? e in erreurs)
          if (ErreurEnvoi.depuisJson(e) case final ErreurEnvoi erreur) erreur,
      ],
    );
  }
}
