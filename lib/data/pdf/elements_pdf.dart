import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/money.dart';
import '../../domain/document_facture.dart';
import '../../domain/regles_entreprise.dart' show formaterSiren;
import 'ressources_pdf.dart';

/// Éléments de mise en page communs aux factures et aux devis : la même charte (bande rose et verte,
/// logo, cartes, tableau, total mis en valeur, pied de page), pour que les deux documents se ressemblent.
/// Fond toujours blanc, même quand l'application est en mode nuit.

const PdfColor pdfRose = PdfColor.fromInt(0xFFD98CA0);
const PdfColor pdfRoseTresClair = PdfColor.fromInt(0xFFFBEAEE);
const PdfColor pdfSauge = PdfColor.fromInt(0xFF7FA98C);
const PdfColor pdfSaugeTexte = PdfColor.fromInt(0xFF4A7359);
const PdfColor pdfPrune = PdfColor.fromInt(0xFF5A2D3B);
const PdfColor pdfEncre = PdfColor.fromInt(0xFF33302E);
const PdfColor pdfDiscret = PdfColor.fromInt(0xFF5E5853);
const PdfColor pdfFilet = PdfColor.fromInt(0xFFE5DCD6);

/// Les quatre graisses de Poppins, chargées une fois pour tout le document.
class PolicesPdf {
  PolicesPdf(RessourcesPdf r)
    : normale = pw.Font.ttf(ByteData.sublistView(r.police)),
      moyenne = pw.Font.ttf(ByteData.sublistView(r.policeMoyenne)),
      semiGrasse = pw.Font.ttf(ByteData.sublistView(r.policeSemiGras)),
      grasse = pw.Font.ttf(ByteData.sublistView(r.policeGras));

  final pw.Font normale;
  final pw.Font moyenne;
  final pw.Font semiGrasse;
  final pw.Font grasse;

  pw.TextStyle style(pw.Font police, double taille, [PdfColor couleur = pdfEncre]) =>
      pw.TextStyle(font: police, fontSize: taille, color: couleur);
}

/// Réglages de page communs : A4, marges et polices.
pw.PageTheme pageThemePdf(PolicesPdf p) => pw.PageTheme(
  pageFormat: PdfPageFormat.a4,
  margin: const pw.EdgeInsets.fromLTRB(42, 50, 42, 62),
  theme: pw.ThemeData.withFont(base: p.normale, bold: p.grasse),
  buildBackground: (pw.Context contexte) => pw.FullPage(ignoreMargins: true, child: bandeDecorative()),
);

/// Garde un bloc d'un seul tenant : un `Stack` n'est pas coupé entre deux pages (une `Column` ou un
/// `Container` le seraient), le bloc passe en entier à la page suivante s'il ne tient pas.
pw.Widget enBloc(pw.Widget bloc) => pw.Stack(children: <pw.Widget>[bloc]);

/// Bande décorative tout en haut de chaque page : rose, avec un bout vert.
pw.Widget bandeDecorative() {
  return pw.Stack(
    children: <pw.Widget>[
      pw.Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(flex: 7, child: pw.Container(height: 14, color: pdfRose)),
            pw.Expanded(flex: 3, child: pw.Container(height: 14, color: pdfSauge)),
          ],
        ),
      ),
    ],
  );
}

/// Sur les pages suivantes : « Facture FACT-2026-0001 (suite) ». Rien sur la première page.
pw.Widget enTeteDeSuite(PolicesPdf p, pw.Context contexte, String libelle) {
  if (contexte.pageNumber == 1) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 14),
    child: pw.Text('$libelle (suite)', style: p.style(p.moyenne, 10, pdfDiscret)),
  );
}

/// Logo, nom de l'entreprise, et à droite le titre du document (« FACTURE », « DEVIS »), son numéro et
/// quelques lignes de dates.
pw.Widget enteteDocument({
  required PolicesPdf p,
  required RessourcesPdf ressources,
  required EmetteurDocument emetteur,
  required String titre,
  required String numero,
  required List<String> dates,
}) {
  final String? responsable = emetteur.responsable;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Image(pw.MemoryImage(ressources.logo), width: 64, height: 64),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(emetteur.nom, style: p.style(p.semiGrasse, 17)),
              if (responsable != null && responsable.isNotEmpty)
                pw.Text(responsable, style: p.style(p.normale, 10, pdfDiscret)),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.Text(titre, style: p.style(p.grasse, 24, pdfPrune)),
          pw.Text('N° $numero', style: p.style(p.moyenne, 11)),
          pw.SizedBox(height: 6),
          for (final String ligne in dates) pw.Text(ligne, style: p.style(p.normale, 9.5)),
        ],
      ),
    ],
  );
}

/// Deux cartes côte à côte : l'émetteur, puis le client ([titreClient] : « FACTURÉ À », « DEVIS POUR »...).
/// Sans nom de client, [clientParDefaut] est imprimé à la place.
pw.Widget partiesDocument({
  required PolicesPdf p,
  required EmetteurDocument emetteur,
  required DestinataireDocument client,
  required String titreClient,
  required String clientParDefaut,
}) {
  final List<String> coordonnees = <String>[
    ...emetteur.adresse,
    if (rempli(emetteur.telephone)) 'Tél. ${emetteur.telephone}',
    if (rempli(emetteur.email)) emetteur.email!,
    if (rempli(emetteur.siren)) 'SIREN ${formaterSiren(emetteur.siren!)}',
  ];

  final List<String> lignesClient = <String>[
    ...client.adresse,
    if (rempli(client.siret)) 'SIRET ${client.siret}',
  ];

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Expanded(child: _carte(p, 'ÉMETTEUR', null, coordonnees)),
      pw.SizedBox(width: 16),
      pw.Expanded(child: _carte(p, titreClient, rempli(client.nom) ? client.nom! : clientParDefaut, lignesClient)),
    ],
  );
}

pw.Widget _carte(PolicesPdf p, String titre, String? nom, List<String> lignes) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(11),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfFilet, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(titre, style: p.style(p.semiGrasse, 8, pdfSaugeTexte)),
        pw.SizedBox(height: 5),
        if (nom != null) pw.Text(nom, style: p.style(p.semiGrasse, 11)),
        for (final String ligne in lignes) pw.Text(ligne, style: p.style(p.normale, 9.5)),
      ],
    ),
  );
}

/// Tableau des lignes : désignation (et description), quantité, prix unitaire, total.
pw.Widget tableauLignes(List<LigneDocument> lignes, PolicesPdf p) {
  pw.Widget cellule(pw.Widget contenu, {pw.Alignment alignement = pw.Alignment.centerLeft}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Align(alignment: alignement, child: contenu),
  );

  pw.Widget titreColonne(String texte, {pw.Alignment alignement = pw.Alignment.centerLeft}) =>
      cellule(pw.Text(texte, style: p.style(p.semiGrasse, 9.5, pdfPrune)), alignement: alignement);

  return pw.Table(
    columnWidths: const <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(),
      1: pw.FixedColumnWidth(38),
      2: pw.FixedColumnWidth(90),
      3: pw.FixedColumnWidth(90),
    },
    children: <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: pdfRoseTresClair, borderRadius: pw.BorderRadius.circular(4)),
        children: <pw.Widget>[
          titreColonne('Désignation'),
          titreColonne('Qté', alignement: pw.Alignment.centerRight),
          titreColonne('Prix unitaire', alignement: pw.Alignment.centerRight),
          titreColonne('Total', alignement: pw.Alignment.centerRight),
        ],
      ),
      for (final LigneDocument ligne in lignes)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: pdfFilet, width: 0.6)),
          ),
          children: <pw.Widget>[
            cellule(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(ligne.designation, style: p.style(p.moyenne, 10)),
                  if (rempli(ligne.description))
                    pw.Text(ligne.description!, style: p.style(p.normale, 8.5, pdfDiscret)),
                ],
              ),
            ),
            cellule(
              pw.Text('${ligne.quantite}', style: p.style(p.normale, 10)),
              alignement: pw.Alignment.centerRight,
            ),
            cellule(
              pw.Text(formatEuros(ligne.prixUnitaireCentimes), style: p.style(p.normale, 10)),
              alignement: pw.Alignment.centerRight,
            ),
            cellule(
              pw.Text(formatEuros(ligne.totalCentimes), style: p.style(p.moyenne, 10)),
              alignement: pw.Alignment.centerRight,
            ),
          ],
        ),
    ],
  );
}

/// Sous-total, remise, frais de port, puis le total dans un encadré rose. Le bloc reste d'un seul tenant
/// (à envelopper dans [enBloc]).
pw.Widget blocTotaux({
  required PolicesPdf p,
  required int sousTotalCentimes,
  required int remiseCentimes,
  required String libelleRemise,
  required int fraisPortCentimes,
  required int totalCentimes,
}) {
  return pw.Container(
    alignment: pw.Alignment.centerRight,
    child: colonneTotaux(
      p: p,
      sousTotalCentimes: sousTotalCentimes,
      remiseCentimes: remiseCentimes,
      libelleRemise: libelleRemise,
      fraisPortCentimes: fraisPortCentimes,
      totalCentimes: totalCentimes,
    ),
  );
}

/// Les totaux eux-mêmes, dans une colonne de largeur fixe (240 pt) : à placer dans une `Row` à côté d'un autre
/// bloc (voir [blocTotaux] pour le bloc aligné à droite sur toute la largeur).
pw.Widget colonneTotaux({
  required PolicesPdf p,
  required int sousTotalCentimes,
  required int remiseCentimes,
  required String libelleRemise,
  required int fraisPortCentimes,
  required int totalCentimes,
}) {
  pw.Widget ligne(String libelle, String montant) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(libelle, style: p.style(p.normale, 10, pdfDiscret)),
        pw.Text(montant, style: p.style(p.moyenne, 10)),
      ],
    ),
  );

  return pw.SizedBox(
    width: 240,
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        ligne('Sous-total', formatEuros(sousTotalCentimes)),
        if (remiseCentimes > 0) ligne(libelleRemise, formatEuros(-remiseCentimes)),
        if (fraisPortCentimes > 0) ligne('Frais de port', formatEuros(fraisPortCentimes)),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            color: pdfRoseTresClair,
            border: pw.Border.all(color: pdfRose, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: <pw.Widget>[
              pw.Text('TOTAL', style: p.style(p.semiGrasse, 12, pdfPrune)),
              pw.Text(formatEuros(totalCentimes), style: p.style(p.grasse, 16, pdfPrune)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Encadré vert de la mention de franchise de TVA.
pw.Widget encadreMentionTva(PolicesPdf p, String texte) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    margin: const pw.EdgeInsets.only(bottom: 12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfSauge, width: 1),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Text(texte, style: p.style(p.moyenne, 10, pdfSaugeTexte)),
  );
}

/// Petite rubrique : titre vert en majuscules, puis le texte.
pw.Widget rubriquePdf(PolicesPdf p, String titre, String texte) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 9),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Text(titre, style: p.style(p.semiGrasse, 8, pdfSaugeTexte)),
      pw.SizedBox(height: 2),
      pw.Text(texte, style: p.style(p.normale, 9.5)),
    ],
  ),
);

/// Pied de page : filet, coordonnées de l'entreprise, nom du document et pagination.
pw.Widget piedDePage({
  required PolicesPdf p,
  required pw.Context contexte,
  required EmetteurDocument emetteur,
  required String libelleDocument,
}) {
  final String identite = <String>[
    emetteur.nom,
    if (rempli(emetteur.siren)) 'SIREN ${formaterSiren(emetteur.siren!)}',
    if (emetteur.adresse.isNotEmpty) emetteur.adresse.join(', '),
    if (rempli(emetteur.telephone)) emetteur.telephone!,
    if (rempli(emetteur.email)) emetteur.email!,
  ].join('  ·  ');

  return pw.Column(
    children: <pw.Widget>[
      pw.Divider(color: pdfFilet, thickness: 0.8),
      pw.SizedBox(height: 4),
      pw.Text(identite, style: p.style(p.normale, 8, pdfDiscret), textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 3),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(libelleDocument, style: p.style(p.normale, 8, pdfDiscret)),
          pw.Text('Page ${contexte.pageNumber} / ${contexte.pagesCount}', style: p.style(p.normale, 8, pdfDiscret)),
        ],
      ),
    ],
  );
}

bool rempli(String? valeur) => valeur != null && valeur.trim().isNotEmpty;
