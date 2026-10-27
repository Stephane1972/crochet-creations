import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_fr.dart';
import '../../domain/document_facture.dart';
import 'elements_pdf.dart';
import 'ressources_pdf.dart';

/// Fabrique le PDF d'une facture (A4, fond blanc) : bande décorative rose et verte, logo, coordonnées,
/// tableau des lignes, total mis en valeur, mention de franchise de TVA, conditions de paiement, IBAN
/// et remerciement s'ils sont renseignés, pied de page. Une facture longue continue sur plusieurs pages.
Future<Uint8List> genererFacturePdf(DocumentFacture d, RessourcesPdf ressources) {
  final PolicesPdf p = PolicesPdf(ressources);
  final pw.Document document = pw.Document(
    title: 'Facture ${d.numero}',
    author: d.emetteur.nom,
    creator: AppConstants.nomApplication,
    subject: 'Facture ${d.numero}',
  );

  document.addPage(
    pw.MultiPage(
      pageTheme: pageThemePdf(p),
      header: (pw.Context contexte) => enTeteDeSuite(p, contexte, 'Facture ${d.numero}'),
      footer: (pw.Context contexte) => piedDePage(
        p: p,
        contexte: contexte,
        emetteur: d.emetteur,
        libelleDocument: 'Facture ${d.numero}',
      ),
      build: (pw.Context contexte) => <pw.Widget>[
        enteteDocument(
          p: p,
          ressources: ressources,
          emetteur: d.emetteur,
          titre: 'FACTURE',
          numero: d.numero,
          dates: <String>[
            'Émise le ${formatDateCourte(d.dateEmission.toLocal())}',
            'Vente / prestation : ${formatDateCourte(d.dateVentePrestation.toLocal())}',
          ],
        ),
        pw.SizedBox(height: 22),
        partiesDocument(
          p: p,
          emetteur: d.emetteur,
          client: d.client,
          titreClient: 'FACTURÉ À',
          clientParDefaut: 'Client de passage',
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
        pw.SizedBox(height: 22),
        enBloc(_mentions(d, p)),
      ],
    ),
  );

  return document.save();
}

/// Mention de franchise de TVA, conditions de paiement, IBAN et remerciement. Le bloc reste d'un seul tenant.
pw.Widget _mentions(DocumentFacture d, PolicesPdf p) {
  return pw.Container(
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        encadreMentionTva(p, d.mentionTva),
        if (rempli(d.conditionsPaiement)) rubriquePdf(p, 'CONDITIONS DE PAIEMENT', d.conditionsPaiement!),
        if (rempli(d.iban)) rubriquePdf(p, 'PAIEMENT PAR VIREMENT', 'IBAN : ${d.iban}'),
        if (rempli(d.messageRemerciement))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(d.messageRemerciement!, style: p.style(p.moyenne, 11, pdfSaugeTexte)),
          ),
      ],
    ),
  );
}
