import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/regles_devis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dates', () {
    test('debutDeJour garde le jour et retire l’heure', () {
      expect(debutDeJour(DateTime(2026, 3, 5, 17, 42)), DateTime(2026, 3, 5));
    });

    test('la validité proposée est 30 jours après la date du devis', () {
      expect(dateValiditeParDefaut(DateTime(2026, 3, 5, 14)), DateTime(2026, 4, 4));
      expect(dateValiditeParDefaut(DateTime(2026, 12, 15)), DateTime(2027, 1, 14));
    });

    test('un devis reste valable toute la journée de sa date limite', () {
      final DateTime limite = DateTime(2026, 6, 30);
      expect(validiteDepassee(limite, DateTime(2026, 6, 29, 23, 59)), isFalse);
      expect(validiteDepassee(limite, DateTime(2026, 6, 30, 0, 0)), isFalse);
      expect(validiteDepassee(limite, DateTime(2026, 6, 30, 23, 59, 59)), isFalse);
      expect(validiteDepassee(limite, DateTime(2026, 7, 1, 0, 0)), isTrue);
    });

    test('sans date limite, un devis ne périme jamais', () {
      expect(validiteDepassee(null, DateTime(2099, 1, 1)), isFalse);
    });
  });

  group('statutAffiche', () {
    final DateTime limite = DateTime(2026, 6, 30);
    final DateTime avant = DateTime(2026, 6, 30, 20);
    final DateTime apres = DateTime(2026, 7, 1, 8);

    test('un brouillon ou un devis envoyé périmé s’affiche « Expiré »', () {
      expect(statutAffiche(StatutDevis.brouillon, limite, apres), StatutDevis.expire);
      expect(statutAffiche(StatutDevis.envoye, limite, apres), StatutDevis.expire);
    });

    test('avant la date limite, le statut ne change pas', () {
      expect(statutAffiche(StatutDevis.brouillon, limite, avant), StatutDevis.brouillon);
      expect(statutAffiche(StatutDevis.envoye, limite, avant), StatutDevis.envoye);
    });

    test('un devis accepté, refusé ou déjà expiré garde son statut', () {
      expect(statutAffiche(StatutDevis.accepte, limite, apres), StatutDevis.accepte);
      expect(statutAffiche(StatutDevis.refuse, limite, apres), StatutDevis.refuse);
      expect(statutAffiche(StatutDevis.expire, limite, avant), StatutDevis.expire);
    });

    test('sans date limite, le statut ne change jamais', () {
      expect(statutAffiche(StatutDevis.envoye, null, apres), StatutDevis.envoye);
    });
  });

  group('statutsPossibles', () {
    test('un brouillon peut être envoyé, accepté ou refusé', () {
      expect(
        statutsPossibles(StatutDevis.brouillon, converti: false),
        <StatutDevis>{StatutDevis.envoye, StatutDevis.accepte, StatutDevis.refuse},
      );
    });

    test('un devis envoyé peut être accepté ou refusé', () {
      expect(
        statutsPossibles(StatutDevis.envoye, converti: false),
        <StatutDevis>{StatutDevis.accepte, StatutDevis.refuse},
      );
    });

    test('un devis accepté, pas encore converti, peut encore être refusé', () {
      expect(statutsPossibles(StatutDevis.accepte, converti: false), <StatutDevis>{StatutDevis.refuse});
    });

    test('un devis refusé, expiré ou converti ne change plus', () {
      expect(statutsPossibles(StatutDevis.refuse, converti: false), isEmpty);
      expect(statutsPossibles(StatutDevis.expire, converti: false), isEmpty);
      for (final StatutDevis statut in StatutDevis.values) {
        expect(statutsPossibles(statut, converti: true), isEmpty, reason: statut.name);
      }
    });
  });

  group('modification et conversion', () {
    test('se modifient : brouillon, envoyé et expiré (pour prolonger la validité)', () {
      for (final StatutDevis statut in <StatutDevis>[StatutDevis.brouillon, StatutDevis.envoye, StatutDevis.expire]) {
        expect(peutEtreModifie(statut, converti: false), isTrue, reason: statut.name);
      }
    });

    test('ne se modifient pas : accepté, refusé, converti', () {
      expect(peutEtreModifie(StatutDevis.accepte, converti: false), isFalse);
      expect(peutEtreModifie(StatutDevis.refuse, converti: false), isFalse);
      expect(peutEtreModifie(StatutDevis.brouillon, converti: true), isFalse);
    });

    test('se convertissent : brouillon, envoyé, accepté (pas déjà converti)', () {
      for (final StatutDevis statut in <StatutDevis>[StatutDevis.brouillon, StatutDevis.envoye, StatutDevis.accepte]) {
        expect(peutEtreConverti(statut, converti: false), isTrue, reason: statut.name);
        expect(peutEtreConverti(statut, converti: true), isFalse, reason: statut.name);
      }
    });

    test('un devis refusé ou expiré ne se convertit pas', () {
      expect(peutEtreConverti(StatutDevis.refuse, converti: false), isFalse);
      expect(peutEtreConverti(StatutDevis.expire, converti: false), isFalse);
    });
  });

  group('verifierDevis', () {
    final DateTime emission = DateTime(2026, 6, 1);
    final DateTime maintenant = DateTime(2026, 6, 1, 10);

    void essayer({DateTime? validite, int acompte = 0, int total = 10000, DateTime? date}) => verifierDevis(
      dateEmission: emission,
      dateValidite: validite,
      acompteCentimes: acompte,
      totalCentimes: total,
      maintenant: date ?? maintenant,
    );

    test('accepte un devis valable le jour même, ou plus tard', () {
      essayer(validite: DateTime(2026, 6, 1));
      essayer(validite: DateTime(2026, 7, 1));
      essayer();
    });

    test('refuse une validité avant la date du devis', () {
      expect(() => essayer(validite: DateTime(2026, 5, 31)), throwsA(isA<DonneeInvalide>()));
    });

    test('refuse une validité déjà passée', () {
      expect(
        () => essayer(validite: DateTime(2026, 6, 2), date: DateTime(2026, 6, 3)),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('déjà passée')),
        ),
      );
    });

    test('accepte un acompte de 0 jusqu’au total', () {
      essayer(acompte: 0);
      essayer(acompte: 3000);
      essayer(acompte: 10000);
    });

    test('refuse un acompte négatif ou supérieur au total', () {
      expect(() => essayer(acompte: -1), throwsA(isA<DonneeInvalide>()));
      expect(
        () => essayer(acompte: 10001),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('100,00')),
        ),
      );
    });
  });
}
