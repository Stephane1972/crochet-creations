import 'dart:io';

import 'package:crochet_creations/data/drive/client_drive.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';

/// Fausse connexion à Google, pour les tests : aucun réseau, aucune fenêtre.
class FauxCompteGoogle implements CompteGoogle {
  FauxCompteGoogle({this.configure = true});

  @override
  bool configure;

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
}

/// Faux Drive en mémoire : les mêmes opérations que [ClientDrive], et rien d'autre (pas de suppression, pas de partage).
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
        if (f.dossierId == dossierId) FichierDistant(id: f.id, nom: f.nom, octets: f.contenu.length, empreinte: f.empreinte),
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
