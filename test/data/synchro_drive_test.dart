import 'dart:convert';
import 'dart:io';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_drive.dart';
import 'package:crochet_creations/data/drive/service_sauvegarde_drive.dart';
import 'package:crochet_creations/data/sauvegarde/espace_libre.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/data/sauvegarde/service_sauvegarde.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/domain/drive_synchro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_drive.dart';

class _EspaceIllimite implements ControleEspaceLibre {
  @override
  Future<int?> octetsLibres(Directory dossier) async => null;
}

/// Un appareil de test (le téléphone ou l'ordinateur) : sa base en mémoire, ses dossiers, ses services et son horloge.
/// Plusieurs appareils partagent le même faux Drive.
class _Appareil {
  _Appareil._(this.db, this.racine, this.drive, this.maintenant);

  static Future<_Appareil> creer(FauxClientDrive drive, DateTime maintenant) async =>
      _Appareil._(creerBaseEnMemoire(), await Directory.systemTemp.createTemp('synchro_drive_'), drive, maintenant);

  final AppDatabase db;
  final Directory racine;
  final FauxClientDrive drive;
  DateTime maintenant;

  Directory dossierLocal(DossierDrive dossier) => Directory('${racine.path}/${dossier.nomLocal}');
  File get fichierEtat => File('${racine.path}/drive/sauvegardes_drive.json');

  late final ServiceSauvegarde sauvegarde = ServiceSauvegarde(
    base: db,
    dossierSauvegardes: Directory('${racine.path}/sauvegardes'),
    dossierExports: Directory('${racine.path}/exports'),
    dossierPhotos: dossierLocal(DossierDrive.photos),
    dossierFactures: dossierLocal(DossierDrive.factures),
    dossierDevis: dossierLocal(DossierDrive.devis),
    dossierPiecesJointes: dossierLocal(DossierDrive.notes),
    horloge: () => maintenant,
    espaceLibre: _EspaceIllimite(),
  );

  late final ServiceDrive envoi = ServiceDrive(
    client: drive,
    dossiers: <DossierDrive, Directory>{for (final DossierDrive d in DossierDrive.values) d: dossierLocal(d)},
    fichierBilan: File('${racine.path}/drive/dernier_envoi.json'),
    horloge: () => maintenant,
  );

  late final ServiceSauvegardeDrive service = ServiceSauvegardeDrive(
    client: drive,
    envoi: envoi,
    sauvegarde: sauvegarde,
    dossierTravail: Directory('${racine.path}/drive/travail'),
    fichierEtat: fichierEtat,
    horloge: () => maintenant,
  );

  /// Saisit un client : les données de cet appareil changent.
  Future<void> saisir(String nom) => db.insererClient(nom: nom);

  Future<List<String>> noms() async {
    final List<Client> lignes = await db.select(db.clients).get();
    return <String>[for (final Client c in lignes) c.nom ?? '']..sort();
  }

  /// Envoie les données sur Drive, à l'heure [heure].
  Future<ResultatSauvegardeDrive> envoyer(DateTime heure) {
    maintenant = heure;
    return service.sauvegarder();
  }

  /// Reprend la sauvegarde la plus récente de Drive.
  Future<void> reprendre(SauvegardeDrive sauvegardeChoisie) async {
    final PreparationRestaurationDrive preparation = await service.preparerRestauration(sauvegardeChoisie);
    await service.restaurer(preparation);
  }

  Future<void> fermer() async {
    await db.close();
    if (await racine.exists()) await racine.delete(recursive: true);
  }
}

final DateTime _lundi = DateTime(2026, 11, 16, 18, 0, 0);
final DateTime _mardi = DateTime(2026, 11, 17, 9, 30, 0);
final DateTime _mercredi = DateTime(2026, 11, 18, 20, 15, 0);

void main() {
  late FauxClientDrive drive;
  late _Appareil telephone;
  late _Appareil ordinateur;

  setUp(() async {
    drive = FauxClientDrive();
    telephone = await _Appareil.creer(drive, _lundi);
    ordinateur = await _Appareil.creer(drive, _lundi);
    addTearDown(telephone.fermer);
    addTearDown(ordinateur.fermer);
  });

  group('l’empreinte et les données vierges', () {
    test('l’empreinte ne change que si les données changent', () async {
      final String avant = await telephone.sauvegarde.empreinteLocale();
      expect(await telephone.sauvegarde.empreinteLocale(), avant);
      await telephone.saisir('Camille');
      expect(await telephone.sauvegarde.empreinteLocale(), isNot(avant));
    });

    test('une installation neuve est vierge (malgré les catégories et lieux de départ) ; dès qu’on saisit, elle ne l’est plus', () async {
      expect(await telephone.sauvegarde.donneesVierges(), isTrue);
      await telephone.saisir('Camille');
      expect(await telephone.sauvegarde.donneesVierges(), isFalse);
    });
  });

  group('constater', () {
    test('rien sur Drive : un appareil neuf est à jour, dès qu’il a des données il a du neuf à envoyer', () async {
      expect((await telephone.service.constater()).situation, SituationSynchro.aJour);
      await telephone.saisir('Camille');
      expect((await telephone.service.constater()).situation, SituationSynchro.aEnvoyer);
    });

    test('ne modifie rien : ni Drive, ni l’état de l’appareil', () async {
      await telephone.saisir('Camille');
      await telephone.service.constater();
      expect(drive.fichiers, isEmpty);
      expect(drive.envoyes, isEmpty);
      expect(await telephone.fichierEtat.exists(), isFalse);
    });

    test('Drive injoignable : l’erreur remonte, rien n’est décidé', () async {
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await expectLater(telephone.service.constater(), throwsA(isA<ErreurDrive>()));
    });

    test('après un envoi : à jour ; une saisie de plus : à envoyer ; la référence est la sauvegarde envoyée', () async {
      await telephone.saisir('Camille');
      final ResultatSauvegardeDrive resultat = await telephone.envoyer(_lundi);
      expect(resultat.issue, IssueSauvegardeDrive.faite);

      final ConstatSynchro constat = await telephone.service.constater();
      expect(constat.situation, SituationSynchro.aJour);
      expect(constat.reference!.nom, nomSauvegardeDrive(_lundi));
      expect(constat.reference!.empreinteLocale, constat.empreinteLocale);

      await telephone.saisir('Dominique');
      expect((await telephone.service.constater()).situation, SituationSynchro.aEnvoyer);
    });

    test('rien de neuf à l’envoi (« déjà à jour ») : la référence est tout de même notée', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      await telephone.fichierEtat.delete(); // l'appareil perd son état : il ne sait plus ce qu'il a envoyé
      final ResultatSauvegardeDrive resultat = await telephone.envoyer(_mardi);
      expect(resultat.issue, IssueSauvegardeDrive.dejaAJour);

      final EtatSauvegardesDrive etat = await telephone.service.lireEtat();
      expect(etat.reference!.nom, nomSauvegardeDrive(_lundi));
      expect((await telephone.service.constater()).situation, SituationSynchro.aJour);
    });

    test('un appareil qui avait envoyé avant la synchronisation (pas de référence) : on ne sait pas s’il a changé', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      // L'ancien fichier d'état : le dernier bilan, sans référence.
      final EtatSauvegardesDrive etat = await telephone.service.lireEtat();
      await telephone.fichierEtat.writeAsString(
        jsonEncode(<String, Object?>{
          'envoiAutomatique': false,
          'derniere': etat.derniere!.versJson(),
          'fichiersNonEnvoyes': <String>[],
        }),
      );

      final ConstatSynchro constat = await telephone.service.constater();
      expect(constat.reference!.nom, nomSauvegardeDrive(_lundi));
      expect(constat.modifieIci, isNull);
      expect(constat.situation, SituationSynchro.aEnvoyer);
    });
  });

  group('d’un appareil à l’autre', () {
    test('l’ordinateur neuf se voit proposer ce que le téléphone a envoyé ; après la reprise, les deux sont à jour', () async {
      await telephone.saisir('Camille');
      await telephone.saisir('Dominique');
      await telephone.envoyer(_lundi);

      ordinateur.maintenant = _mardi;
      final ConstatSynchro propose = await ordinateur.service.constater();
      expect(propose.situation, SituationSynchro.aReprendre);
      expect(propose.distante!.nom, nomSauvegardeDrive(_lundi));

      await ordinateur.reprendre(propose.distante!);
      expect(await ordinateur.noms(), <String>['Camille', 'Dominique']);

      final ConstatSynchro apres = await ordinateur.service.constater();
      expect(apres.situation, SituationSynchro.aJour);
      expect(apres.reference!.nom, nomSauvegardeDrive(_lundi));
      expect(apres.reference!.empreinteLocale, apres.empreinteLocale);
      // Le téléphone, lui, n'a rien à reprendre : Drive n'a rien de plus récent que ce qu'il a envoyé.
      expect((await telephone.service.constater()).situation, SituationSynchro.aJour);
    });

    test('l’ordinateur envoie sa version : le téléphone, resté inchangé, se la voit proposer', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      ordinateur.maintenant = _mardi;
      await ordinateur.reprendre((await ordinateur.service.constater()).distante!);

      await ordinateur.saisir('Dominique');
      expect((await ordinateur.service.constater()).situation, SituationSynchro.aEnvoyer);
      await ordinateur.envoyer(_mardi);

      telephone.maintenant = _mercredi;
      final ConstatSynchro constat = await telephone.service.constater();
      expect(constat.situation, SituationSynchro.aReprendre);
      expect(constat.distante!.nom, nomSauvegardeDrive(_mardi));

      await telephone.reprendre(constat.distante!);
      expect(await telephone.noms(), <String>['Camille', 'Dominique']);
      expect((await telephone.service.constater()).situation, SituationSynchro.aJour);
    });

    test('les deux ont changé : la personne choisit, et rien n’est ni envoyé ni remplacé par la comparaison', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      ordinateur.maintenant = _mardi;
      await ordinateur.reprendre((await ordinateur.service.constater()).distante!);

      // Chacun saisit de son côté ; l'ordinateur envoie d'abord.
      await ordinateur.saisir('Dominique');
      await ordinateur.envoyer(_mardi);
      await telephone.saisir('Eloïse');

      telephone.maintenant = _mercredi;
      final int envoyesAvant = drive.envoyes.length;
      final ConstatSynchro constat = await telephone.service.constater();
      expect(constat.situation, SituationSynchro.aChoisir);
      expect(constat.modifieIci, isTrue);
      expect(drive.envoyes, hasLength(envoyesAvant));
      expect(await telephone.noms(), <String>['Camille', 'Eloïse']);
    });

    test('« garder cet appareil » : la version de l’ordinateur reste sur Drive, et le prochain envoi la dépasse', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      ordinateur.maintenant = _mardi;
      await ordinateur.reprendre((await ordinateur.service.constater()).distante!);
      await ordinateur.saisir('Dominique');
      await ordinateur.envoyer(_mardi);
      await telephone.saisir('Eloïse');

      telephone.maintenant = _mercredi;
      final ConstatSynchro constat = await telephone.service.constater();
      expect(constat.situation, SituationSynchro.aChoisir);

      await telephone.service.garderCetAppareil(constat.distante!);
      final ConstatSynchro apres = await telephone.service.constater();
      expect(apres.situation, SituationSynchro.aEnvoyer);
      expect(apres.demandeUneDecision, isFalse);

      await telephone.envoyer(_mercredi);
      // Rien n'a été supprimé sur Drive : les trois versions y sont, la plus récente est celle du téléphone.
      final List<SauvegardeDrive> versions = await telephone.service.listerSauvegardes();
      expect(versions.map((SauvegardeDrive s) => s.nom), <String>[
        nomSauvegardeDrive(_mercredi),
        nomSauvegardeDrive(_mardi),
        nomSauvegardeDrive(_lundi),
      ]);
      // L'ordinateur, inchangé depuis son envoi, se voit proposer la version du téléphone.
      ordinateur.maintenant = _mercredi.add(const Duration(hours: 1));
      expect((await ordinateur.service.constater()).situation, SituationSynchro.aReprendre);
    });

    test('« reprendre » dans le cas des deux changements : les données de l’appareil sont remplacées par celles de Drive', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      ordinateur.maintenant = _mardi;
      await ordinateur.reprendre((await ordinateur.service.constater()).distante!);
      await ordinateur.saisir('Dominique');
      await ordinateur.envoyer(_mardi);
      await telephone.saisir('Eloïse');

      telephone.maintenant = _mercredi;
      final ConstatSynchro constat = await telephone.service.constater();
      await telephone.reprendre(constat.distante!);

      expect(await telephone.noms(), <String>['Camille', 'Dominique']);
      expect((await telephone.service.constater()).situation, SituationSynchro.aJour);
      // La copie de sécurité faite juste avant la restauration garde ce qui était saisi sur le téléphone.
      final List<SauvegardeLocale> copies = await telephone.sauvegarde.lister();
      expect(copies.where((SauvegardeLocale c) => c.type == TypeSauvegarde.avantRestauration), isNotEmpty);
    });

    test('restaurer à la main une version plus ancienne fait d’elle la référence', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      await telephone.saisir('Dominique');
      await telephone.envoyer(_mardi);

      final List<SauvegardeDrive> versions = await telephone.service.listerSauvegardes();
      final SauvegardeDrive ancienne = versions.last;
      expect(ancienne.nom, nomSauvegardeDrive(_lundi));
      await telephone.reprendre(ancienne);

      final EtatSauvegardesDrive etat = await telephone.service.lireEtat();
      expect(etat.reference!.nom, nomSauvegardeDrive(_lundi));
      expect(await telephone.noms(), <String>['Camille']);
      // La version du mardi est plus récente que celle qu'on vient de reprendre, et rien n'a changé ici : on la propose.
      expect((await telephone.service.constater()).situation, SituationSynchro.aReprendre);
    });

    test('une reprise efface la liste des fichiers « pas partis » : ils ne sont plus ceux de cet appareil', () async {
      await telephone.saisir('Camille');
      await telephone.envoyer(_lundi);
      ordinateur.maintenant = _mardi;
      final ConstatSynchro constat = await ordinateur.service.constater();
      await ordinateur.reprendre(constat.distante!);
      expect((await ordinateur.service.lireEtat()).fichiersNonEnvoyes, isEmpty);
    });
  });
}
