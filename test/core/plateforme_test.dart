import 'package:crochet_creations/core/plateforme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plateforme', () {
    test('Android : tout est disponible, l’interface est celle du téléphone', () {
      const Plateforme p = Plateforme.android();
      expect(p.nom, 'Android');
      expect(p.appareilPhoto, isTrue);
      expect(p.googleDrive, isTrue);
      expect(p.fenetreDeBureau, isFalse);
    });

    test('Windows : ni appareil photo ni Google Drive, une fenêtre d’ordinateur', () {
      const Plateforme p = Plateforme.windows();
      expect(p.nom, 'Windows');
      expect(p.appareilPhoto, isFalse);
      expect(p.googleDrive, isFalse);
      expect(p.fenetreDeBureau, isTrue);
    });

    test('hors Windows (ici Linux, comme tous les tests), la plateforme courante est celle d’Android', () {
      final Plateforme p = Plateforme.courante();
      expect(p.nom, 'Android');
      expect(p.appareilPhoto, isTrue);
      expect(p.googleDrive, isTrue);
      expect(p.fenetreDeBureau, isFalse);
    });

    test('le contenu d’une fenêtre d’ordinateur a la largeur d’un grand téléphone', () {
      expect(Plateforme.largeurMaxContenu, inInclusiveRange(480, 800));
    });
  });
}
