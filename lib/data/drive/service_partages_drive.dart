import 'dart:io';

import '../../domain/drive_envoi.dart';
import '../../domain/drive_partage.dart';
import 'client_drive.dart';
import 'compte_google.dart';

/// Les fichiers de chaque rubrique partageable, dans l'ordre où on les montre.
typedef FichiersPartageables = Map<RubriquePartage, List<FichierDistant>>;

/// Partage de fichiers de Drive (étape 8) : voir qui y a accès, partager en lecture avec une personne précise, activer ou
/// retirer un lien, envoyer le catalogue dans le dossier « Exports ».
///
/// Les principes sont ceux de `drive_partage.dart` : **rien ne se fait sans un geste de la personne** (ce service n'est appelé
/// que depuis l'écran « Partages »), un partage ne donne que le droit de lire, seules les rubriques [RubriquePartage] sont
/// proposées (jamais les sauvegardes), et arrêter un partage retire un accès sans toucher au fichier.
class ServicePartagesDrive {
  ServicePartagesDrive({required ClientDrive client}) : _client = client;

  final ClientDrive _client;

  /// Les dossiers Drive des rubriques, retrouvés (ou créés si [creer]). Une rubrique sans dossier n'a pas d'entrée.
  Future<Map<RubriquePartage, String>> _dossiers({required bool creer}) async {
    String? racine = await _client.trouverDossier(nomDossierRacineDrive);
    if (racine == null) {
      if (!creer) return const <RubriquePartage, String>{};
      racine = await _client.creerDossier(nomDossierRacineDrive);
    }
    final Map<RubriquePartage, String> ids = <RubriquePartage, String>{};
    for (final RubriquePartage rubrique in RubriquePartage.values) {
      String? id = await _client.trouverDossier(rubrique.nomDrive, parentId: racine);
      if (id == null && creer) id = await _client.creerDossier(rubrique.nomDrive, parentId: racine);
      if (id != null) ids[rubrique] = id;
    }
    return ids;
  }

  /// Les fichiers de chaque rubrique, sans rien créer sur Drive. Les plus récemment nommés d'abord (les numéros de facture et
  /// de devis, et les dates des exports, croissent avec le temps). Une rubrique sans dossier, ou vide, a une liste vide.
  Future<FichiersPartageables> lister() async {
    final Map<RubriquePartage, String> ids = await _dossiers(creer: false);
    final FichiersPartageables resultat = <RubriquePartage, List<FichierDistant>>{};
    for (final RubriquePartage rubrique in RubriquePartage.values) {
      final String? id = ids[rubrique];
      final List<FichierDistant> fichiers = id == null ? <FichierDistant>[] : List<FichierDistant>.of(await _client.lister(id));
      fichiers.sort((FichierDistant a, FichierDistant b) => b.nom.compareTo(a.nom));
      resultat[rubrique] = fichiers;
    }
    return resultat;
  }

  /// Qui a accès au fichier.
  Future<AccesFichier> acces(String fichierId) async => AccesFichier(await _client.listerAcces(fichierId));

  /// L'adresse du fichier dans Drive (seules les personnes qui y ont accès peuvent l'ouvrir).
  Future<String?> lien(String fichierId) => _client.lienDuFichier(fichierId);

  /// Partage le fichier, en lecture, avec [email] (Google prévient la personne par e-mail). L'adresse est vérifiée avant tout
  /// appel : une [ErreurDrive] dit pourquoi elle ne convient pas. Retourne les accès à jour.
  Future<AccesFichier> partagerAvec(String fichierId, String email, {String? emailProprietaire}) async {
    final AccesFichier avant = await acces(fichierId);
    final String? probleme = erreurCourrielPartage(
      email,
      emailProprietaire: emailProprietaire,
      dejaPartagees: <String>[
        for (final AccesDrive a in avant.personnes)
          if (a.email != null) a.email!,
      ],
    );
    if (probleme != null) throw ErreurDrive(probleme);
    await _client.partagerAvec(fichierId: fichierId, email: normaliserCourriel(email));
    return acces(fichierId);
  }

  /// Active le lien (lecture seule pour toute personne qui l'a) et retourne l'adresse à donner. Sans effet si le lien est déjà
  /// actif. L'écran demande une confirmation avant d'appeler cette méthode.
  Future<String?> activerLien(String fichierId) async {
    final AccesFichier avant = await acces(fichierId);
    if (avant.lienPublic == null) await _client.activerLienPublic(fichierId);
    return _client.lienDuFichier(fichierId);
  }

  /// Retire un accès (une personne, ou le lien public). Le propriétaire ne se retire pas. Retourne les accès à jour.
  Future<AccesFichier> retirer(String fichierId, AccesDrive aRetirer) async {
    if (aRetirer.type == TypeAcces.proprietaire) {
      throw const ErreurDrive('Le propriétaire du fichier ne peut pas être retiré.');
    }
    await _client.retirerAcces(fichierId: fichierId, accesId: aRetirer.id);
    return acces(fichierId);
  }

  /// Envoie l'archive du catalogue dans le dossier « Exports » de Drive. Un fichier du même nom (le même jour) est remplacé :
  /// ceux qui y ont accès voient la nouvelle version (l'ancienne reste dans l'historique du fichier sur Drive). Retourne `true`
  /// si un fichier existant a été remplacé.
  Future<bool> envoyerExport(File archive, {void Function(int octetsEnvoyes)? progression}) async {
    final Map<RubriquePartage, String> ids = await _dossiers(creer: true);
    final String dossierId = ids[RubriquePartage.exports]!;
    final String nom = archive.uri.pathSegments.last;
    String? existant;
    for (final FichierDistant f in await _client.lister(dossierId)) {
      if (f.nom == nom) {
        existant = f.id;
        break;
      }
    }
    await _client.envoyer(
      fichier: archive,
      nom: nom,
      dossierId: dossierId,
      idExistant: existant,
      progression: progression,
    );
    return existant != null;
  }
}
