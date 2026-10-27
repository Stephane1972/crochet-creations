import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../domain/document_devis.dart';
import 'elements_pdf.dart';
import 'ressources_pdf.dart';

/// Fabrique le PDF d'un devis, dans la même mise en page que les factures : bande rose et verte, logo,
/// coordonnées, tableau des lignes, total mis en valeur, puis les conditions du devis (validité, délai de
/// réalisation, acompte), la mention de franchise de TVA et le bloc « Bon pour accord » à signer.
Future<Uint8List> genererDevisPdf(DocumentDevis d, RessourcesPdf ressources) {
  final PolicesPdf p = PolicesPdf(ressources);
  final pw.Document document = pw.Document(
    title: 'Devis ${d.numero}',
    author: d.emetteur.nom,
    creator: AppConstants.nomApplication,
    subject: 'Devis ${d.numero}',
  );

  final DateTime? validite = d.dateValidite;
  document.addPage(
    pw.MultiPage(
      pageTheme: pageThemePdf(p),
      header: (pw.Context contexte) => enTeteDeSuite(p, contexte, 'Devis ${d.numero}'),
      footer: (pw.Context contexte) => piedDePage(
        p: p,
        contexte: contexte,
        emetteur: d.emetteur,
        libelleDocument: 'Devis ${d.numero}',
      ),
      build: (pw.Context contexte) => <pw.Widget>[
        enteteDocument(
          p: p,
          ressources: ressources,
          emetteur: d.emetteur,
          titre: 'DEVIS',
          numero: d.numero,
          dates: <String>[
            'Établi le ${formatDateCourte(d.dateEmission.toLocal())}',
            if (validite != null) 'Valable jusqu’au ${formatDateCourte(validite.toLocal())}',
          ],
        ),
        pw.SizedBox(height: 22),
        partiesDocument(
          p: p,
          emetteur: d.emetteur,
          client: d.client,
          titreClient: 'DEVIS ÉTABLI POUR',
          clientParDefaut: 'Client non précisé',
        ),
        pw.SizedBox(height: 22),
        tableauLignes(d.lignes, p),
        pw.SizedBox(height: 14),
        enBloc(
          blocTotaux(
            p: p,
            sousTotalCentimes: d.sousTotalCentimes,
            remiseCentimes: d.remiseCentimes,
            libelleRemise: d.libelleRemise,
            fraisPortCentimes: d.fraisPortCentimes,
            totalCentimes: d.totalCentimes,
          ),
        ),
        pw.SizedBox(height: 16),
        enBloc(_conditions(d, p)),
        pw.SizedBox(height: 10),
        enBloc(_bonPourAccord(p)),
      ],
    ),
  );

  return document.save();
}

/// Mention de franchise de TVA, puis validité, délai de réalisation, acompte demandé (et IBAN pour le régler)
/// sur deux colonnes, pour que le devis tienne sur une page.
pw.Widget _conditions(DocumentDevis d, PolicesPdf p) {
  final DateTime? validite = d.dateValidite;
  final String? delai = rempli(d.delaiRealisation) ? d.delaiRealisation!.trim() : null;
  final bool acompte = d.acompteCentimes > 0;

  final List<pw.Widget> rubriques = <pw.Widget>[
    if (validite != null)
      rubriquePdf(p, 'VALIDITÉ DU DEVIS', 'Valable jusqu’au ${formatDateCourte(validite.toLocal())}.'),
    if (delai != null) rubriquePdf(p, 'DÉLAI DE RÉALISATION', delai),
    if (acompte)
      rubriquePdf(p, 'ACOMPTE DEMANDÉ', '${formatEuros(d.acompteCentimes)} à verser à l’acceptation du devis.'),
    if (acompte && rempli(d.iban)) rubriquePdf(p, 'PAIEMENT PAR VIREMENT', 'IBAN : ${d.iban}'),
  ];

  return pw.Container(
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        encadreMentionTva(p, d.mentionTva),
        for (int i = 0; i < rubriques.length; i += 2)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(child: rubriques[i]),
              pw.SizedBox(width: 16),
              pw.Expanded(child: i + 1 < rubriques.length ? rubriques[i + 1] : pw.SizedBox()),
            ],
          ),
      ],
    ),
  );
}

/// Cadre à signer : « Bon pour accord », date et signature du client.
pw.Widget _bonPourAccord(PolicesPdf p) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfRose, width: 1),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text('BON POUR ACCORD', style: p.style(p.semiGrasse, 11, pdfPrune)),
        pw.SizedBox(height: 3),
        pw.Text(
          'Date et signature du client, précédées de la mention manuscrite « Bon pour accord ».',
          style: p.style(p.normale, 9, pdfDiscret),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(child: _zoneASigner(p, 'Date :')),
            pw.SizedBox(width: 16),
            pw.Expanded(flex: 2, child: _zoneASigner(p, 'Signature :')),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _zoneASigner(PolicesPdf p, String titre) {
  return pw.Container(
    height: 46,
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfFilet, width: 0.8),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(titre, style: p.style(p.normale, 8.5, pdfDiscret)),
  );
}
