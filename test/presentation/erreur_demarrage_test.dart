import 'package:crochet_creations/presentation/startup/erreur_demarrage_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('l’écran d’erreur explique quoi faire et affiche le détail technique', (tester) async {
    await tester.pumpWidget(const ErreurDemarrageApp(erreur: 'base illisible (test)'));

    expect(find.text('Impossible d’ouvrir vos données'), findsOneWidget);
    expect(find.textContaining('Ce message n’efface rien'), findsOneWidget);
    expect(find.text('base illisible (test)'), findsOneWidget);
  });
}
