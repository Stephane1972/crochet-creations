import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/domain/drive_synchro.dart';
import 'package:flutter_test/flutter_test.dart';

SauvegardeDrive _sauvegarde(DateTime date) =>
    SauvegardeDrive(id: 'id-${date.millisecondsSinceEpoch}', nom: nomSauvegardeDrive(date), date: date);

ReferenceSynchro _reference(DateTime date, {String? empreinte}) =>
    ReferenceSynchro(nom: nomSauvegardeDrive(date), date: date, empreinteLocale: empreinte);

final DateTime _lundi = DateTime(2026, 11, 16, 18, 0, 0);
final DateTime _mardi = DateTime(2026, 11, 17, 9, 30, 0);

void main() {
  group('constaterSynchro : rien de plus récent sur Drive', () {
    test('la dernière version de Drive est celle qu’on a envoyée, et rien n’a changé : à jour', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'A',
      );
      expect(constat.situation, SituationSynchro.aJour);
      expect(constat.modifieIci, isFalse);
      expect(constat.demandeUneDecision, isFalse);
    });

    test('la dernière version de Drive est celle qu’on a envoyée, mais on a changé depuis : à envoyer', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'B',
      );
      expect(constat.situation, SituationSynchro.aEnvoyer);
      expect(constat.modifieIci, isTrue);
      expect(constat.demandeUneDecision, isFalse);
    });

    test('une référence d’avant la synchronisation (sans empreinte) : on ne sait pas, donc à envoyer', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi),
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'A',
      );
      expect(constat.situation, SituationSynchro.aEnvoyer);
      expect(constat.modifieIci, isNull);
    });

    test('des fichiers qui n’ont pas pu partir la dernière fois : à envoyer, même sans changement', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'A',
        fichiersEnAttente: true,
      );
      expect(constat.situation, SituationSynchro.aEnvoyer);
    });

    test('rien sur Drive : un appareil qui a des données les envoie, un appareil tout neuf n’a rien à envoyer', () {
      expect(
        constaterSynchro(reference: null, distante: null, empreinteLocale: 'A').situation,
        SituationSynchro.aEnvoyer,
      );
      expect(
        constaterSynchro(reference: null, distante: null, empreinteLocale: 'A', donneesVierges: true).situation,
        SituationSynchro.aJour,
      );
    });

    test('la sauvegarde de référence a disparu de Drive (il n’en reste que de plus anciennes) : pas une nouveauté', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_mardi, empreinte: 'A'),
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'A',
      );
      expect(constat.situation, SituationSynchro.aJour);
    });
  });

  group('constaterSynchro : Drive a une version plus récente, envoyée d’ailleurs', () {
    test('rien n’a changé ici : on propose de la reprendre', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_mardi),
        empreinteLocale: 'A',
      );
      expect(constat.situation, SituationSynchro.aReprendre);
      expect(constat.demandeUneDecision, isTrue);
      expect(constat.distante!.date, _mardi);
    });

    test('les deux ont changé : la personne choisit, il n’y a pas de fusion', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_mardi),
        empreinteLocale: 'B',
      );
      expect(constat.situation, SituationSynchro.aChoisir);
      expect(constat.modifieIci, isTrue);
      expect(constat.demandeUneDecision, isTrue);
    });

    test('on ne sait pas si cet appareil a changé : la personne choisit, rien n’est écrasé en silence', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi),
        distante: _sauvegarde(_mardi),
        empreinteLocale: 'A',
      );
      expect(constat.situation, SituationSynchro.aChoisir);
      expect(constat.modifieIci, isNull);
    });

    test('jamais synchronisé, avec des données : la personne choisit', () {
      final ConstatSynchro constat = constaterSynchro(reference: null, distante: _sauvegarde(_lundi), empreinteLocale: 'A');
      expect(constat.situation, SituationSynchro.aChoisir);
    });

    test('jamais synchronisé, mais installation toute neuve : on propose de reprendre', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: null,
        distante: _sauvegarde(_lundi),
        empreinteLocale: 'A',
        donneesVierges: true,
      );
      expect(constat.situation, SituationSynchro.aReprendre);
    });

    test('des données vierges ne comptent que pour un appareil jamais synchronisé', () {
      final ConstatSynchro constat = constaterSynchro(
        reference: _reference(_lundi, empreinte: 'A'),
        distante: _sauvegarde(_mardi),
        empreinteLocale: 'B',
        donneesVierges: true,
      );
      expect(constat.situation, SituationSynchro.aChoisir);
    });
  });

  group('envoi en arrière-plan', () {
    test('le premier est permis, le suivant attend dix minutes', () {
      final DateTime maintenant = DateTime(2026, 11, 17, 10, 0);
      expect(envoiEnArrierePlanPermis(null, maintenant), isTrue);
      expect(envoiEnArrierePlanPermis(maintenant.subtract(const Duration(minutes: 9, seconds: 59)), maintenant), isFalse);
      expect(envoiEnArrierePlanPermis(maintenant.subtract(delaiEntreEnvoisEnArrierePlan), maintenant), isTrue);
    });

    test('une horloge qui a reculé ne bloque pas l’envoi', () {
      final DateTime maintenant = DateTime(2026, 11, 17, 10, 0);
      expect(envoiEnArrierePlanPermis(maintenant.add(const Duration(hours: 1)), maintenant), isTrue);
    });
  });

  group('ReferenceSynchro', () {
    test('s’enregistre en JSON et se relit à l’identique', () {
      final ReferenceSynchro reference = _reference(_lundi, empreinte: 'abc');
      final ReferenceSynchro? relue = ReferenceSynchro.depuisJson(reference.versJson());
      expect(relue!.nom, reference.nom);
      expect(relue.date, _lundi);
      expect(relue.empreinteLocale, 'abc');
    });

    test('sans empreinte, elle se relit sans empreinte ; un contenu abîmé donne null', () {
      expect(ReferenceSynchro.depuisJson(_reference(_lundi).versJson())!.empreinteLocale, isNull);
      for (final Object? json in <Object?>[null, 'x', 3, <String, Object?>{}, <String, Object?>{'nom': 'a', 'date': 'pas une date'}]) {
        expect(ReferenceSynchro.depuisJson(json), isNull, reason: '$json');
      }
    });

    test('l’état des sauvegardes la garde, et un ancien fichier d’état (sans référence) reste lisible', () {
      final EtatSauvegardesDrive etat = const EtatSauvegardesDrive().copier(reference: _reference(_lundi, empreinte: 'abc'));
      expect(EtatSauvegardesDrive.depuisJson(etat.versJson()).reference!.empreinteLocale, 'abc');
      expect(EtatSauvegardesDrive.depuisJson(<String, Object?>{'envoiAutomatique': true}).reference, isNull);
    });
  });
}
