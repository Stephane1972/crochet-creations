import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../domain/document_facture.dart';
import '../../domain/regles_entreprise.dart' show formaterSiren;
import 'ressources_pdf.dart';

// Couleurs de la charte (fond toujours blanc, même quand l'application est en mode nuit).
const PdfColor _rose = PdfColor.fromInt(0xFFD98CA0);
const PdfColor _roseTresClair = PdfColor.fromInt(0xFFFBEAEE);
const PdfColor _sauge = PdfColor.fromInt(0xFF7FA98C);
const PdfColor _saugeTexte = PdfColor.fromInt(0xFF4A7359);
const PdfColor _prune = PdfColor.fromInt(0xFF5A2D3B);
const PdfColor _encre = PdfColor.fromInt(0xFF33302E);
const PdfColor _discret = PdfColor.fromInt(0xFF5E5853);
const PdfColor _filet = PdfColor.fromInt(0xFFE5DCD6);

/// Fabrique le PDF d'une facture (A4, fond blanc) : bande décorative rose et verte, logo, coordonnées,
/// tableau des lignes, total mis en valeur, mention de franchise de TVA, conditions de paiement, IBAN
/// et remerciement s'ils sont renseignés, pied de page. Une facture longue continue sur plusieurs pages.
Future<Uint8List> genererFacturePdf(DocumentFacture d, RessourcesPdf ressources) {
  final _Polices p = _Polices(ressources);
  final pw.Document document = pw.Document(
    title: 'Facture ${d.numero}',
    author: d.emetteur.nom,
    creator: AppConstants.nomApplication,
    subject: 'Facture ${d.numero}',
  );

  document.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 50, 42, 62),
        theme: pw.ThemeData.withFont(base: p.normale, bold: p.grasse),
        buildBackground: (pw.Context contexte) => pw.FullPage(ignoreMargins: true, child: _bande()),
      ),
      header: (pw.Context contexte) => contexte.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Text('Facture ${d.numero} (suite)', style: p.style(p.moyenne, 10, _discret)),
            ),
      footer: (pw.Context contexte) => _pied(d, contexte, p),
      build: (pw.Context contexte) => <pw.Widget>[
        _entete(d, ressources, p),
        pw.SizedBox(height: 22),
        _parties(d, p),
        pw.SizedBox(height: 22),
        _tableau(d, p),
        pw.SizedBox(height: 14),
        _totaux(d, p),
        pw.SizedBox(height: 22),
        _mentions(d, p),
      ],
    ),
  );

  return document.save();
}

/// Les quatre graisses de Poppins, chargées une fois pour tout le document.
class _Polices {
  _Polices(RessourcesPdf r)
    : normale = pw.Font.ttf(ByteData.sublistView(r.police)),
      moyenne = pw.Font.ttf(ByteData.sublistView(r.policeMoyenne)),
      semiGrasse = pw.Font.ttf(ByteData.sublistView(r.policeSemiGras)),
      grasse = pw.Font.ttf(ByteData.sublistView(r.policeGras));

  final pw.Font normale;
  final pw.Font moyenne;
  final pw.Font semiGrasse;
  final pw.Font grasse;

  pw.TextStyle style(pw.Font police, double taille, [PdfColor couleur = _encre]) =>
      pw.TextStyle(font: police, fontSize: taille, color: couleur);
}

/// Bande décorative tout en haut de chaque page : rose, avec un bout vert.
pw.Widget _bande() {
  return pw.Stack(
    children: <pw.Widget>[
      pw.Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(flex: 7, child: pw.Container(height: 14, color: _rose)),
            pw.Expanded(flex: 3, child: pw.Container(height: 14, color: _sauge)),
          ],
        ),
      ),
    ],
  );
}

/// Logo, nom de l'entreprise, et à droite le titre « FACTURE » avec son numéro et ses dates.
pw.Widget _entete(DocumentFacture d, RessourcesPdf ressources, _Polices p) {
  final String? responsable = d.emetteur.responsable;
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
              pw.Text(d.emetteur.nom, style: p.style(p.semiGrasse, 17)),
              if (responsable != null && responsable.isNotEmpty)
                pw.Text(responsable, style: p.style(p.normale, 10, _discret)),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.Text('FACTURE', style: p.style(p.grasse, 24, _prune)),
          pw.Text('N° ${d.numero}', style: p.style(p.moyenne, 11)),
          pw.SizedBox(height: 6),
          pw.Text('Émise le ${formatDateCourte(d.dateEmission.toLocal())}', style: p.style(p.normale, 9.5)),
          pw.Text(
            'Vente / prestation : ${formatDateCourte(d.dateVentePrestation.toLocal())}',
            style: p.style(p.normale, 9.5),
          ),
        ],
      ),
    ],
  );
}

/// Deux cartes côte à côte : l'émetteur, puis le client.
pw.Widget _parties(DocumentFacture d, _Polices p) {
  final EmetteurDocument e = d.emetteur;
  final List<String> coordonnees = <String>[
    ...e.adresse,
    if (_rempli(e.telephone)) 'Tél. ${e.telephone}',
    if (_rempli(e.email)) e.email!,
    if (_rempli(e.siren)) 'SIREN ${formaterSiren(e.siren!)}',
  ];

  final DestinataireDocument c = d.client;
  final List<String> lignesClient = <String>[
    ...c.adresse,
    if (_rempli(c.siret)) 'SIRET ${c.siret}',
  ];

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Expanded(child: _carte(p, 'ÉMETTEUR', null, coordonnees)),
      pw.SizedBox(width: 16),
      pw.Expanded(child: _carte(p, 'FACTURÉ À', _rempli(c.nom) ? c.nom! : 'Client de passage', lignesClient)),
    ],
  );
}

pw.Widget _carte(_Polices p, String titre, String? nom, List<String> lignes) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(11),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _filet, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(titre, style: p.style(p.semiGrasse, 8, _saugeTexte)),
        pw.SizedBox(height: 5),
        if (nom != null) pw.Text(nom, style: p.style(p.semiGrasse, 11)),
        for (final String ligne in lignes) pw.Text(ligne, style: p.style(p.normale, 9.5)),
      ],
    ),
  );
}

/// Tableau des lignes : désignation (et description), quantité, prix unitaire, total.
pw.Widget _tableau(DocumentFacture d, _Polices p) {
  pw.Widget cellule(pw.Widget contenu, {pw.Alignment alignement = pw.Alignment.centerLeft}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Align(alignment: alignement, child: contenu),
  );

  pw.Widget titreColonne(String texte, {pw.Alignment alignement = pw.Alignment.centerLeft}) =>
      cellule(pw.Text(texte, style: p.style(p.semiGrasse, 9.5, _prune)), alignement: alignement);

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
        decoration: pw.BoxDecoration(color: _roseTresClair, borderRadius: pw.BorderRadius.circular(4)),
        children: <pw.Widget>[
          titreColonne('Désignation'),
          titreColonne('Qté', alignement: pw.Alignment.centerRight),
          titreColonne('Prix unitaire', alignement: pw.Alignment.centerRight),
          titreColonne('Total', alignement: pw.Alignment.centerRight),
        ],
      ),
      for (final LigneDocument ligne in d.lignes)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _filet, width: 0.6)),
          ),
          children: <pw.Widget>[
            cellule(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(ligne.designation, style: p.style(p.moyenne, 10)),
                  if (_rempli(ligne.description))
                    pw.Text(ligne.description!, style: p.style(p.normale, 8.5, _discret)),
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

/// Sous-total, remise, frais de port, puis le total dans un encadré rose. Le bloc reste d'un seul tenant.
pw.Widget _totaux(DocumentFacture d, _Polices p) {
  pw.Widget ligne(String libelle, String montant) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(libelle, style: p.style(p.normale, 10, _discret)),
        pw.Text(montant, style: p.style(p.moyenne, 10)),
      ],
    ),
  );

  return pw.Container(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 240,
      child: pw.Column(
        children: <pw.Widget>[
          ligne('Sous-total', formatEuros(d.sousTotalCentimes)),
          if (d.remiseCentimes > 0) ligne(d.libelleRemise, formatEuros(-d.remiseCentimes)),
          if (d.fraisPortCentimes > 0) ligne('Frais de port', formatEuros(d.fraisPortCentimes)),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: _roseTresClair,
              border: pw.Border.all(color: _rose, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text('TOTAL', style: p.style(p.semiGrasse, 12, _prune)),
                pw.Text(formatEuros(d.totalCentimes), style: p.style(p.grasse, 16, _prune)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Mention de franchise de TVA, conditions de paiement, IBAN et remerciement. Le bloc reste d'un seul tenant.
pw.Widget _mentions(DocumentFacture d, _Polices p) {
  pw.Widget rubrique(String titre, String texte) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 9),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(titre, style: p.style(p.semiGrasse, 8, _saugeTexte)),
        pw.SizedBox(height: 2),
        pw.Text(texte, style: p.style(p.normale, 9.5)),
      ],
    ),
  );

  return pw.Container(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          margin: const pw.EdgeInsets.only(bottom: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _sauge, width: 1),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Text(d.mentionTva, style: p.style(p.moyenne, 10, _saugeTexte)),
        ),
        if (_rempli(d.conditionsPaiement)) rubrique('CONDITIONS DE PAIEMENT', d.conditionsPaiement!),
        if (_rempli(d.iban)) rubrique('PAIEMENT PAR VIREMENT', 'IBAN : ${d.iban}'),
        if (_rempli(d.messageRemerciement))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(d.messageRemerciement!, style: p.style(p.moyenne, 11, _saugeTexte)),
          ),
      ],
    ),
  );
}

/// Pied de page : filet, coordonnées de l'entreprise, numéro de la facture et pagination.
pw.Widget _pied(DocumentFacture d, pw.Context contexte, _Polices p) {
  final EmetteurDocument e = d.emetteur;
  final String identite = <String>[
    e.nom,
    if (_rempli(e.siren)) 'SIREN ${formaterSiren(e.siren!)}',
    if (e.adresse.isNotEmpty) e.adresse.join(', '),
    if (_rempli(e.telephone)) e.telephone!,
    if (_rempli(e.email)) e.email!,
  ].join('  ·  ');

  return pw.Column(
    children: <pw.Widget>[
      pw.Divider(color: _filet, thickness: 0.8),
      pw.SizedBox(height: 4),
      pw.Text(identite, style: p.style(p.normale, 8, _discret), textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 3),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('Facture ${d.numero}', style: p.style(p.normale, 8, _discret)),
          pw.Text('Page ${contexte.pageNumber} / ${contexte.pagesCount}', style: p.style(p.normale, 8, _discret)),
        ],
      ),
    ],
  );
}

bool _rempli(String? valeur) => valeur != null && valeur.trim().isNotEmpty;
