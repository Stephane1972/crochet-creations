import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;

import '../../core/utils/date_fr.dart';
import '../../domain/csv.dart';
import '../../domain/lieux_vente.dart';
import '../database/app_database.dart';
import '../repositories/client_vues.dart' show nomClientOuCopie;
import '../repositories/produit_vues.dart' show nomClientAffiche;
import 'format_sauvegarde.dart';

/// Export des données en CSV (étape 11) : **un fichier CSV par type de données**, réunis dans un seul `.zip`.
///
/// Fichiers : produits, clients, ventes, factures, devis, cours, inscriptions, dépenses. Pensés pour être
/// ouverts dans un tableur (ou donnés à un comptable) : en-têtes en français, montants en euros avec deux
/// décimales (`12,50`), dates en `05/03/2026`, listes de choix en toutes lettres. Les éléments archivés
/// sont inclus, avec leur date d'archivage.
///
/// Ce n'est **pas** une sauvegarde : un CSV ne peut pas être restauré (voir `ServiceSauvegarde`).
class ExportCsv {
  ExportCsv(this._base, {DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final DateTime Function() _horloge;

  /// Noms des fichiers du `.zip`, dans l'ordre.
  static const List<String> fichiers = <String>[
    'produits.csv',
    'clients.csv',
    'ventes.csv',
    'factures.csv',
    'devis.csv',
    'cours.csv',
    'inscriptions.csv',
    'depenses.csv',
  ];

  /// Le texte de chaque CSV (nom du fichier → contenu), lu d'un seul tenant dans la base.
  Future<Map<String, String>> fabriquerTextes() {
    return _base.transaction(() async {
      return <String, String>{
        'produits.csv': await _produits(),
        'clients.csv': await _clients(),
        'ventes.csv': await _ventes(),
        'factures.csv': await _factures(),
        'devis.csv': await _devis(),
        'cours.csv': await _cours(),
        'inscriptions.csv': await _inscriptions(),
        'depenses.csv': await _depenses(),
      };
    });
  }

  /// Le `.zip` : un CSV par type. Chaque fichier commence par la marque UTF-8 (BOM), qu'Excel attend pour
  /// afficher correctement les accents.
  Future<Uint8List> fabriquerArchive() async {
    final Map<String, String> textes = await fabriquerTextes();
    final Archive archive = Archive();
    for (final MapEntry<String, String> texte in textes.entries) {
      archive.add(ArchiveFile.bytes(texte.key, <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(texte.value)]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Nom du fichier d'export du jour : `crochet-creations-export-csv-2026-10-31.zip`.
  String nomArchive() => 'crochet-creations-export-csv-${_jour(_horloge())}.zip';

  /// Fabrique l'archive et l'écrit dans [dossier] (un fichier du même nom est remplacé).
  Future<File> ecrireArchive(Directory dossier) async {
    final File fichier = File('${dossier.path}${Platform.pathSeparator}${nomArchive()}');
    await ecrireAtomiquement(fichier, await fabriquerArchive());
    return fichier;
  }

  // ---------------------------------------------------------------------------
  // Un CSV par type de données
  // ---------------------------------------------------------------------------

  Future<String> _produits() async {
    final List<Produit> produits = await _base.select(_base.produits).get();
    produits.sort((Produit a, Produit b) => a.reference.compareTo(b.reference));
    final List<VarianteProduit> variantes = await _base.select(_base.variantesProduit).get();
    variantes.sort((VarianteProduit a, VarianteProduit b) => a.id.compareTo(b.id));
    final Map<int, List<VarianteProduit>> variantesDe = <int, List<VarianteProduit>>{};
    for (final VarianteProduit v in variantes) {
      if (v.archiveLe != null) continue;
      variantesDe.putIfAbsent(v.produitId, () => <VarianteProduit>[]).add(v);
    }
    final Map<String, String> nomsCategories = <String, String>{
      for (final CategorieProduit c in await _base.select(_base.categoriesProduit).get()) c.cle: c.nom,
    };

    return construireCsv(
      <String>[
        'Référence',
        'Nom',
        'Catégorie',
        'Statut',
        'Prix de vente (€)',
        'Coût des matières (€)',
        'Stock (produit sans variantes)',
        'Seuil d’alerte',
        'Variantes (stock)',
        'Personnalisable',
        'Couleur',
        'Dimensions',
        'Matières',
        'Temps de fabrication (min)',
        'Description',
        'Créé le',
        'Archivé le',
      ],
      <List<String>>[
        for (final Produit p in produits)
          <String>[
            p.reference,
            p.nom,
            nomsCategories[p.categorie] ?? p.categorie,
            p.statut.libelle,
            montantCsv(p.prixVenteCentimes),
            montantCsv(p.coutMatiereCentimes),
            '${p.quantiteStock}',
            '${p.seuilAlerteStock}',
            (variantesDe[p.id] ?? const <VarianteProduit>[])
                .map((VarianteProduit v) => '${v.libelle} (${v.quantiteStock})')
                .join(', '),
            _ouiNon(p.personnalisable),
            p.couleur ?? '',
            p.dimensions ?? '',
            p.matieres ?? '',
            p.tempsFabricationMinutes?.toString() ?? '',
            p.description ?? '',
            _date(p.creeLe),
            _dateOuVide(p.archiveLe),
          ],
      ],
    );
  }

  Future<String> _clients() async {
    final List<Client> clients = await _base.select(_base.clients).get();
    clients.sort((Client a, Client b) => _nomClient(a).toLowerCase().compareTo(_nomClient(b).toLowerCase()));
    return construireCsv(
      <String>[
        'Type',
        'Civilité',
        'Prénom',
        'Nom',
        'Raison sociale',
        'Téléphone',
        'E-mail',
        'Adresse',
        'Code postal',
        'Ville',
        'SIREN / SIRET',
        'Notes',
        'Créé le',
        'Archivé le',
      ],
      <List<String>>[
        for (final Client c in clients)
          <String>[
            c.typeClient.libelle,
            c.civilite?.libelle ?? '',
            c.prenom ?? '',
            c.nom ?? '',
            c.raisonSociale ?? '',
            c.telephone ?? '',
            c.email ?? '',
            c.adresse ?? '',
            c.codePostal ?? '',
            c.ville ?? '',
            c.siret ?? '',
            c.notes ?? '',
            _date(c.creeLe),
            _dateOuVide(c.archiveLe),
          ],
      ],
    );
  }

  Future<String> _ventes() async {
    final List<Vente> ventes = await _base.select(_base.ventes).get();
    ventes.sort((Vente a, Vente b) {
      final int parDate = a.dateVente.compareTo(b.dateVente);
      return parDate != 0 ? parDate : a.id.compareTo(b.id);
    });
    final Map<int, String> noms = await _nomsClients();
    final Map<int, String> lieux = <int, String>{
      for (final LieuVente l in await _base.select(_base.lieuxVente).get()) l.id: l.nom,
    };

    final List<LigneVente> lignes = await _base.select(_base.lignesVente).get();
    lignes.sort((LigneVente a, LigneVente b) {
      final int parPosition = a.position.compareTo(b.position);
      return parPosition != 0 ? parPosition : a.id.compareTo(b.id);
    });
    final Map<int, List<String>> articlesDe = <int, List<String>>{};
    for (final LigneVente l in lignes) {
      articlesDe.putIfAbsent(l.venteId, () => <String>[]).add('${l.quantite} × ${l.designation}');
    }

    final Map<int, int> encaisseDe = <int, int>{};
    for (final Paiement p in await _base.select(_base.paiements).get()) {
      encaisseDe[p.venteId] = (encaisseDe[p.venteId] ?? 0) + p.montantCentimes;
    }

    return construireCsv(
      <String>[
        'N° de vente',
        'Date',
        'Client',
        'Lieu de vente',
        'Statut',
        'Paiement',
        'Articles',
        'Sous-total (€)',
        'Remise (€)',
        'Frais de port (€)',
        'Total (€)',
        'Encaissé (€)',
        'Notes',
      ],
      <List<String>>[
        for (final Vente v in ventes)
          <String>[
            '${v.id}',
            _date(v.dateVente),
            _clientOuPassage(noms, v.clientId, v.clientNom),
            lieux[v.lieuId] ?? libelleLieuNonRenseigne,
            v.statut.libelle,
            v.statutPaiement.libelle,
            (articlesDe[v.id] ?? const <String>[]).join(' ; '),
            montantCsv(v.sousTotalCentimes),
            montantCsv(v.remiseCentimes),
            montantCsv(v.fraisPortCentimes),
            montantCsv(v.totalCentimes),
            montantCsv(encaisseDe[v.id] ?? 0),
            v.notes ?? '',
          ],
      ],
    );
  }

  Future<String> _factures() async {
    final List<Facture> factures = await _base.select(_base.factures).get();
    factures.sort((Facture a, Facture b) => a.numero.compareTo(b.numero));
    return construireCsv(
      <String>[
        'Numéro',
        'Date d’émission',
        'Date de la vente',
        'Échéance',
        'Client',
        'Total (€)',
        'Statut',
        'N° de vente',
        'Mention TVA',
      ],
      <List<String>>[
        for (final Facture f in factures)
          <String>[
            f.numero,
            _date(f.dateEmission),
            _date(f.dateVentePrestation),
            _dateOuVide(f.dateEcheance),
            f.clientNom ?? '',
            montantCsv(f.totalCentimes),
            f.statut.libelle,
            '${f.venteId}',
            f.mentionTva,
          ],
      ],
    );
  }

  Future<String> _devis() async {
    final List<DevisFiche> devis = await _base.select(_base.devis).get();
    devis.sort((DevisFiche a, DevisFiche b) => a.numero.compareTo(b.numero));
    final Map<int, String> noms = await _nomsClients();
    return construireCsv(
      <String>[
        'Numéro',
        'Date d’émission',
        'Valable jusqu’au',
        'Client',
        'Statut',
        'Sous-total (€)',
        'Remise (€)',
        'Frais de port (€)',
        'Total (€)',
        'Acompte (€)',
        'Délai de réalisation',
        'N° de vente (si converti)',
        'Notes',
      ],
      <List<String>>[
        for (final DevisFiche d in devis)
          <String>[
            d.numero,
            _date(d.dateEmission),
            _dateOuVide(d.dateValidite),
            d.clientId == null ? nomClientOuCopie(copie: d.clientNom, sinon: '') : (noms[d.clientId] ?? ''),
            d.statut.libelle,
            montantCsv(d.sousTotalCentimes),
            montantCsv(d.remiseCentimes),
            montantCsv(d.fraisPortCentimes),
            montantCsv(d.totalCentimes),
            montantCsv(d.acompteCentimes),
            d.delaiRealisation ?? '',
            d.venteId?.toString() ?? '',
            d.notes ?? '',
          ],
      ],
    );
  }

  Future<String> _cours() async {
    final List<CoursFiche> cours = await _base.select(_base.cours).get();
    cours.sort((CoursFiche a, CoursFiche b) => a.debutLe.compareTo(b.debutLe));
    return construireCsv(
      <String>[
        'Titre',
        'Date',
        'Heure',
        'Durée (min)',
        'Lieu',
        'Prix (€)',
        'Places',
        'Niveau',
        'Matériel inclus',
        'Statut',
        'Description',
        'Archivé le',
      ],
      <List<String>>[
        for (final CoursFiche c in cours)
          <String>[
            c.titre,
            _date(c.debutLe),
            _heure(c.debutLe),
            '${c.dureeMinutes}',
            c.lieu ?? '',
            montantCsv(c.prixCentimes),
            '${c.places}',
            c.niveau.libelle,
            _ouiNon(c.materielInclus),
            c.statut.libelle,
            c.description ?? '',
            _dateOuVide(c.archiveLe),
          ],
      ],
    );
  }

  Future<String> _inscriptions() async {
    final List<Inscription> inscriptions = await _base.select(_base.inscriptionsCours).get();
    final Map<int, CoursFiche> cours = <int, CoursFiche>{
      for (final CoursFiche c in await _base.select(_base.cours).get()) c.id: c,
    };
    final Map<int, String> noms = await _nomsClients();
    inscriptions.sort((Inscription a, Inscription b) {
      final DateTime? debutA = cours[a.coursId]?.debutLe;
      final DateTime? debutB = cours[b.coursId]?.debutLe;
      if (debutA != null && debutB != null) {
        final int parCours = debutA.compareTo(debutB);
        if (parCours != 0) return parCours;
      }
      return a.dateInscription.compareTo(b.dateInscription);
    });
    return construireCsv(
      <String>[
        'Cours',
        'Date du cours',
        'Client',
        'Statut',
        'Date d’inscription',
        'Prix (€)',
        'N° de vente',
        'Notes',
      ],
      <List<String>>[
        for (final Inscription i in inscriptions)
          <String>[
            cours[i.coursId]?.titre ?? '',
            cours[i.coursId] == null ? '' : _date(cours[i.coursId]!.debutLe),
            noms[i.clientId] ?? '',
            i.statut.libelle,
            _date(i.dateInscription),
            montantCsv(i.prixCentimes),
            i.venteId?.toString() ?? '',
            i.notes ?? '',
          ],
      ],
    );
  }

  Future<String> _depenses() async {
    final List<Depense> depenses = await _base.select(_base.depenses).get();
    depenses.sort((Depense a, Depense b) {
      final int parDate = a.dateDepense.compareTo(b.dateDepense);
      return parDate != 0 ? parDate : a.id.compareTo(b.id);
    });
    final Map<int, String> produits = <int, String>{
      for (final Produit p in await _base.select(_base.produits).get()) p.id: p.nom,
    };
    return construireCsv(
      <String>[
        'Date',
        'Catégorie',
        'Montant (€)',
        'Fournisseur',
        'Description',
        'Produit concerné',
        'Archivée le',
      ],
      <List<String>>[
        for (final Depense d in depenses)
          <String>[
            _date(d.dateDepense),
            d.categorie.libelle,
            montantCsv(d.montantCentimes),
            d.fournisseur ?? '',
            d.description ?? '',
            d.produitId == null ? '' : (produits[d.produitId] ?? ''),
            _dateOuVide(d.archiveLe),
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Petites aides
  // ---------------------------------------------------------------------------

  /// Nom de chaque client (identifiant → « Prénom Nom » ou raison sociale).
  Future<Map<int, String>> _nomsClients() async {
    final List<Client> clients = await _base.select(_base.clients).get();
    return <int, String>{for (final Client c in clients) c.id: _nomClient(c)};
  }

  String _nomClient(Client c) =>
      nomClientAffiche(prenom: c.prenom, nom: c.nom, raisonSociale: c.raisonSociale);

  /// Le client d'une vente : sa fiche, sinon le nom copié quand la fiche a été supprimée, sinon « Client de passage ».
  String _clientOuPassage(Map<int, String> noms, int? clientId, String? copie) {
    if (clientId == null) return nomClientOuCopie(copie: copie, sinon: 'Client de passage');
    return noms[clientId] ?? '';
  }

  String _date(DateTime date) => formatDateCourte(date);

  String _dateOuVide(DateTime? date) => date == null ? '' : formatDateCourte(date);

  String _ouiNon(bool valeur) => valeur ? 'Oui' : 'Non';

  /// « 14:30 » : une heure qu'un tableur reconnaît (« 14 h 30 » serait du texte).
  String _heure(DateTime date) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(date.hour)}:${deux(date.minute)}';
  }

  String _jour(DateTime date) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${deux(date.month)}-${deux(date.day)}';
  }
}
