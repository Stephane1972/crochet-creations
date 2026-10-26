import 'dart:io';
import 'dart:typed_data';

import 'package:crochet_creations/data/pdf/ressources_pdf.dart';
import 'package:crochet_creations/domain/document_facture.dart';

/// Polices et logo lus directement dans le dossier `assets/` (les tests s'exécutent à la racine du projet).
RessourcesPdf ressourcesPdfDeTest() {
  Uint8List lire(String chemin) => File(chemin).readAsBytesSync();
  return RessourcesPdf(
    police: lire('assets/fonts/Poppins-Regular.ttf'),
    policeMoyenne: lire('assets/fonts/Poppins-Medium.ttf'),
    policeSemiGras: lire('assets/fonts/Poppins-SemiBold.ttf'),
    policeGras: lire('assets/fonts/Poppins-Bold.ttf'),
    logo: lire('assets/images/logo_mono.png'),
  );
}

/// Nombre de pages d'un PDF.
int nombreDePages(Uint8List pdf) {
  final String texte = String.fromCharCodes(pdf);
  return RegExp(r'/Type\s*/Page(?![A-Za-z])').allMatches(texte).length;
}

/// Écrit un exemple dans `build/exemples_pdf/` : la CI le publie avec l'APK pour vérifier la mise en page.
void ecrireExemplePdf(String nom, Uint8List pdf) {
  final Directory dossier = Directory('build/exemples_pdf')..createSync(recursive: true);
  File('${dossier.path}/$nom.pdf').writeAsBytesSync(pdf);
}

/// L'entreprise des exemples de PDF.
const EmetteurDocument emetteurDeTest = EmetteurDocument(
  nom: 'Crochet & Créations',
  responsable: 'Camille Martin',
  adresse: <String>['12 rue des Lilas', '31000 Toulouse'],
  telephone: '06 12 34 56 78',
  email: 'contact@exemple.fr',
  siren: '123456789',
);
