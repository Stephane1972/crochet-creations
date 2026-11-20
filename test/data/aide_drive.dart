import 'dart:io';

import 'package:crochet_creations/data/drive/client_drive.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_partage.dart';
import 'package:crochet_creations/domain/id_client_google.dart';

/// Fausse connexion à Google, pour les tests : aucun réseau, aucune fenêtre.
class FauxCompteGoogle implements CompteGoogle {
  FauxCompteGoogle({this.configure = true});

  @override
  bool configure;

  /// L'ID client Web saisi dans l'application (`null` : aucun), et ce qu'on avait avant de le saisir.
  String? idEnregistre;
  bool? _configureAvant;

  /// Vrai pour simuler un ID qu'il faut fermer complètement l'application pour prendre en compte.
  @override
  bool redemarrageNecessaire = false;

  /// Si défini, `enregistrerClientWeb` échoue avec cette erreur.
  ErreurDrive? erreurDEnregistrement;

  @override
  String get clientWeb => configure ? (idEnregistre ?? 'fourni-123456$suffixeIdClientGoogle') : '';

  @override
  bool get clientWebEnregistre => idEnregistre != null;

  @override
  Future<void> enregistrerClientWeb(String saisie) async {
    final ErreurDrive? erreur = erreurDEnregistrement;
    if (erreur != null) throw erreur;
    final String id = nettoyerIdClientWeb(saisie);
    final String? probleme = erreurIdClientWeb(id);
    if (probleme != null) throw ErreurDrive(probleme);
    _configureAvant ??= configure;
    idEnregistre = id;
    configure = true;
  }

  @override
  Future<void> oublierClientWeb() async {
    idEnregistre = null;
    configure = _configureAvant ?? configure;
    _configureAvant = null;
  }

  /// Le compte que `restaurer` retrouve au lancement (`null` : personne n'est connecté).
  ProfilGoogle? dejaConnecte;

  /// Le compte choisi quand la personne se connecte.
  ProfilGoogle profilDeConnexion = const ProfilGoogle(email: 'stef@exemple.fr', nom: 'Stéphane');

  /// Si défini, `seConnecter` échoue avec cette erreur.
  ErreurDrive? erreurDeConnexion;

  /// Si défini, `jetonAcces` échoue avec cette erreur.
  ErreurDrive? erreurDeJeton;

  int connexions = 0;
  int deconnexions = 0;
  int jetonsInvalides = 0;
  ProfilGoogle? courant;

  @override
  Future<ProfilGoogle?> restaurer() async {
    courant = dejaConnecte;
    return courant;
  }

  @override
  Future<ProfilGoogle> seConnecter() async {
    connexions++;
    final ErreurDrive? erreur = erreurDeConnexion;
    if (erreur != null) throw erreur;
    courant = profilDeConnexion;
    return profilDeConnexion;
  }

  @override
  Future<void> seDeconnecter() async {
    deconnexions++;
    courant = null;
  }

  @override
  Future<String> jetonAcces() async {
    final ErreurDrive? erreur = erreurDeJeton;
    if (erreur != null) throw erreur;
    return 'jeton-de-test';
  }

  @override
  void invaliderJeton() => jetonsInvalides++;
}

/// Faux compte Google « application de bureau » (Windows) : en plus de l'ID, un code secret est demandé.
class FauxCompteGoogleBureau extends FauxCompteGoogle implements CompteAvecCodeSecret {
  FauxCompteGoogleBureau() : super(configure: false);

  /// Le code secret saisi (`null` : aucun).
  String? codeSecret;

  @override
  bool get codeSecretEnregistre => codeSecret != null;

  @override
  Future<void> enregistrerClientWeb(String saisie) async {
    await super.enregistrerClientWeb(saisie);
    configure = codeSecret != null;
  }

  @override
  Future<void> enregistrerCodeSecret(String saisie) async {
    final String code = nettoyerCodeSecretGoogle(saisie);
    final String? probleme = erreurCodeSecretGoogle(code);
    if (probleme != null) throw ErreurDrive(probleme);
    codeSecret = code;
    configure = idEnregistre != null;
  }
}

/// Un dossier du faux Drive.
class DossierDriveFaux {
  DossierDriveFaux({required this.nom, required this.parentId});

  final String nom;
  final String parentId;
}

/// Un fichier du faux Drive.
class FichierDriveFaux {
  FichierDriveFaux({required this.id, required this.nom, required this.dossierId, required this.contenu, this.empreinte});

  final String id;
  final String nom;
  final String dossierId;
  List<int> contenu;
  String? empreinte;

  /// Nombre de fois où le contenu a été envoyé (1 = jamais remplacé).
  int versions = 1;

  /// Les accès donnés par l'application ou posés à la main dans un test (le propriétaire n'y figure pas : le faux Drive
  /// l'ajoute toujours en premier).
  final List<AccesDrive> acces = <AccesDrive>[];
}

/// Faux Drive en mémoire : les mêmes opérations que [ClientDrive], et rien d'autre (pas de suppression de fichier).
class FauxClientDrive implements ClientDrive {
  final Map<String, DossierDriveFaux> dossiers = <String, DossierDriveFaux>{};
  final Map<String, FichierDriveFaux> fichiers = <String, FichierDriveFaux>{};
  int _suite = 0;

  /// Décide si l'envoi du fichier [nom] échoue : retourne l'erreur à lever, ou `null`.
  ErreurDrive? Function(String nom)? echecEnvoi;

  /// Si défini, chaque opération échoue avec cette erreur (Google injoignable, droit retiré).
  ErreurDrive? panne;

  /// Appelé juste avant chaque envoi (permet, par exemple, de demander l'arrêt pendant l'envoi).
  void Function(String nom)? avantEnvoi;

  /// Si défini, chaque envoi attend la fin de ce que retourne cette fonction (permet de « garder » un envoi en cours pour
  /// regarder l'écran, puis de le laisser finir).
  Future<void> Function(String nom)? pauseEnvoi;

  /// Si défini, le téléchargement du fichier [nom] échoue avec cette erreur (retourne `null` : il réussit).
  ErreurDrive? Function(String nom)? echecTelechargement;

  /// Si défini, l'envoi du fichier [nom] est accepté mais Drive ne le garde pas (pour tester la vérification d'une sauvegarde
  /// qu'on ne retrouve pas).
  bool Function(String nom)? oublierEnvoi;

  /// Si défini, chaque téléchargement attend la fin de ce que retourne cette fonction.
  Future<void> Function(String nom)? pauseTelechargement;

  int dossiersCrees = 0;

  /// Adresses que Google refuserait (une adresse inventée, par exemple) : le partage échoue avec un message lisible.
  final Set<String> adressesRefusees = <String>{};

  /// Si défini, la lecture ou la modification des accès du fichier [id] échoue avec cette erreur (retourne `null` : elle réussit).
  ErreurDrive? Function(String id)? echecAcces;

  /// Chaque partage demandé, sous la forme « nom du fichier | adresse ».
  final List<String> partagesDemandes = <String>[];

  /// Chaque lien activé (nom du fichier), et chaque accès retiré (« nom du fichier | libellé »).
  final List<String> liensActives = <String>[];
  final List<String> accesRetires = <String>[];

  /// Le propriétaire de tous les fichiers du faux Drive.
  static const AccesDrive proprietaire = AccesDrive(
    id: 'perm-proprietaire',
    type: TypeAcces.proprietaire,
    email: 'stef@exemple.fr',
    nom: 'Stéphane',
  );

  /// Noms des fichiers envoyés (créés ou mis à jour), dans l'ordre.
  final List<String> envoyes = <String>[];

  /// Noms des fichiers téléchargés, dans l'ordre.
  final List<String> telecharges = <String>[];

  void _verifierPanne() {
    final ErreurDrive? erreur = panne;
    if (erreur != null) throw erreur;
  }

  @override
  Future<String?> trouverDossier(String nom, {String? parentId}) async {
    _verifierPanne();
    for (final MapEntry<String, DossierDriveFaux> d in dossiers.entries) {
      if (d.value.nom == nom && d.value.parentId == (parentId ?? 'root')) return d.key;
    }
    return null;
  }

  @override
  Future<String> creerDossier(String nom, {String? parentId}) async {
    _verifierPanne();
    final String id = 'dossier-${++_suite}';
    dossiers[id] = DossierDriveFaux(nom: nom, parentId: parentId ?? 'root');
    dossiersCrees++;
    return id;
  }

  @override
  Future<List<FichierDistant>> lister(String dossierId) async {
    _verifierPanne();
    return <FichierDistant>[
      for (final FichierDriveFaux f in fichiers.values)
        if (f.dossierId == dossierId)
          FichierDistant(
            id: f.id,
            nom: f.nom,
            octets: f.contenu.length,
            empreinte: f.empreinte,
            partage: f.acces.isNotEmpty,
            lien: 'https://drive.exemple.fr/fichier/${f.id}',
          ),
    ];
  }

  @override
  Future<void> envoyer({
    required File fichier,
    required String nom,
    required String dossierId,
    String? empreinte,
    String? idExistant,
    void Function(int octetsEnvoyes)? progression,
  }) async {
    _verifierPanne();
    avantEnvoi?.call(nom);
    await pauseEnvoi?.call(nom);
    final ErreurDrive? erreur = echecEnvoi?.call(nom);
    if (erreur != null) throw erreur;
    final List<int> octets = await fichier.readAsBytes();
    progression?.call(octets.length);
    if (oublierEnvoi?.call(nom) ?? false) {
      envoyes.add(nom);
      return;
    }
    if (idExistant == null) {
      final String id = 'fichier-${++_suite}';
      fichiers[id] = FichierDriveFaux(id: id, nom: nom, dossierId: dossierId, contenu: octets, empreinte: empreinte);
    } else {
      final FichierDriveFaux existant = fichiers[idExistant]!;
      existant.contenu = octets;
      existant.empreinte = empreinte;
      existant.versions++;
    }
    envoyes.add(nom);
  }

  @override
  Future<void> telecharger({
    required String id,
    required File destination,
    void Function(int octetsRecus)? progression,
  }) async {
    _verifierPanne();
    final FichierDriveFaux? fichier = fichiers[id];
    if (fichier == null) throw const ErreurDrive('Le fichier ou le dossier est introuvable sur Drive.');
    await pauseTelechargement?.call(fichier.nom);
    final ErreurDrive? erreur = echecTelechargement?.call(fichier.nom);
    if (erreur != null) throw erreur;
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(fichier.contenu);
    progression?.call(fichier.contenu.length);
    telecharges.add(fichier.nom);
  }

  // --- Partage -------------------------------------------------------------------

  FichierDriveFaux _fichierPartage(String id) {
    _verifierPanne();
    final FichierDriveFaux? fichier = fichiers[id];
    if (fichier == null) throw const ErreurDrive('Le fichier ou le dossier est introuvable sur Drive.');
    final ErreurDrive? erreur = echecAcces?.call(id);
    if (erreur != null) throw erreur;
    return fichier;
  }

  @override
  Future<List<AccesDrive>> listerAcces(String fichierId) async {
    final FichierDriveFaux fichier = _fichierPartage(fichierId);
    return <AccesDrive>[proprietaire, ...fichier.acces];
  }

  @override
  Future<void> partagerAvec({required String fichierId, required String email}) async {
    final FichierDriveFaux fichier = _fichierPartage(fichierId);
    if (adressesRefusees.contains(email)) {
      throw const ErreurDrive('Google n’a pas accepté de partager avec cette adresse. Vérifiez qu’elle est exacte.');
    }
    fichier.acces.add(AccesDrive(id: 'perm-${++_suite}', type: TypeAcces.personne, email: email, nom: null));
    partagesDemandes.add('${fichier.nom} | $email');
  }

  @override
  Future<void> activerLienPublic(String fichierId) async {
    final FichierDriveFaux fichier = _fichierPartage(fichierId);
    fichier.acces.add(AccesDrive(id: 'perm-${++_suite}', type: TypeAcces.lienPublic));
    liensActives.add(fichier.nom);
  }

  @override
  Future<void> retirerAcces({required String fichierId, required String accesId}) async {
    final FichierDriveFaux fichier = _fichierPartage(fichierId);
    if (accesId == proprietaire.id) throw const ErreurDrive('Le propriétaire du fichier ne peut pas être retiré.');
    final int rang = fichier.acces.indexWhere((AccesDrive a) => a.id == accesId);
    if (rang < 0) throw const ErreurDrive('Le fichier ou le dossier est introuvable sur Drive.');
    final AccesDrive retire = fichier.acces.removeAt(rang);
    accesRetires.add('${fichier.nom} | ${retire.libelle}');
  }

  @override
  Future<String?> lienDuFichier(String fichierId) async {
    _fichierPartage(fichierId);
    return 'https://drive.exemple.fr/fichier/$fichierId';
  }

  // --- Pour vérifier -----------------------------------------------------------

  /// Identifiant du dossier [nomDrive] placé sous « Un p'tit crochet dans les stocks » (`null` : il n'existe pas).
  String? idSousDossier(String nomDrive) {
    String? racine;
    for (final MapEntry<String, DossierDriveFaux> d in dossiers.entries) {
      if (d.value.nom == nomDossierRacineDrive && d.value.parentId == 'root') racine = d.key;
    }
    if (racine == null) return null;
    for (final MapEntry<String, DossierDriveFaux> d in dossiers.entries) {
      if (d.value.nom == nomDrive && d.value.parentId == racine) return d.key;
    }
    return null;
  }

  /// Les noms des fichiers du sous-dossier [nomDrive], triés.
  List<String> nomsDans(String nomDrive) {
    final String? id = idSousDossier(nomDrive);
    if (id == null) return const <String>[];
    return <String>[
      for (final FichierDriveFaux f in fichiers.values)
        if (f.dossierId == id) f.nom,
    ]..sort();
  }

  /// Un fichier du faux Drive par son nom (`null` : absent).
  FichierDriveFaux? fichierNomme(String nom) {
    for (final FichierDriveFaux f in fichiers.values) {
      if (f.nom == nom) return f;
    }
    return null;
  }
}
