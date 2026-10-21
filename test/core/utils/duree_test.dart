import 'package:crochet_creations/core/utils/duree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moins d’une heure', () {
    expect(formatDuree(45), '45 min');
    expect(formatDuree(5), '5 min');
  });

  test('heures rondes', () {
    expect(formatDuree(60), '1 h');
    expect(formatDuree(120), '2 h');
  });

  test('heures et minutes', () {
    expect(formatDuree(150), '2 h 30');
    expect(formatDuree(65), '1 h 05');
  });

  test('durée nulle ou négative', () {
    expect(formatDuree(0), '0 min');
    expect(formatDuree(-10), '0 min');
  });
}
