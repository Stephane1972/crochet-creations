import 'package:drift/drift.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/duree.dart';
import '../../core/utils/texte.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_cours.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import 'cours_vues.dart';
import 'vente_repository.dart';

/// Ce que l'utilisatrice saisit pour un cours.
class DonneesCours {
  const DonneesCours({
    required this.titre,
    this.description,
    required this.debutLe,
    required this.dureeMinutes,
    this.lieu,
    required this.prixCentimes,
    required this.places,
    this.niveau = NiveauCours.tousNiveaux,
    this.materielInclus = false,
    this.photoChemin,
  });

  final String titre;
  final String? description;

  /// Date et heure de début.
  final DateTime debutLe;
  final int dureeMinutes;
  final String? lieu;

  /// Prix par personne ; 0 = cours gratuit.
  final int prixCentimes;
  final int places;
  final NiveauCours niveau;
  final bool materielInclus;

  /// Nom du fichier de la photo (voir `StockagePhotos`) ; `null` = pas de photo.
  final String? photoChemin;
}

/// Cours de crochet et inscriptions.
///
/// - Un cours a un nombre de **places** : les inscriptions confirmées les occupent, les suivantes vont en
///   **liste d'attente**. Quand une place se libère, on **confirme** à la main la première personne en attente.
/// - Chaque inscription confirmée crée une **vente** (une ligne « cours », sans effet sur le stock) : le paiement
///   (payé, acompte ou plus tard), la facture et l'encaissement du solde se font comme pour toute vente. Une
///   personne en liste d'attente n'a pas encore de vente.
/// - Annuler une inscription annule la vente (avec remboursement du net encaissé), sauf si on choisit de garder
///   le paiement reçu. Annuler un **cours** ne touche pas aux inscriptions : on les traite une par une.
/// - Un cours ne se supprime pas : annulé, ou archivé une fois terminé.
class CoursRepository {
  CoursRepository(this._db, this._ventes);

  final AppDatabase _db;
  final VenteRepository _ventes;

  // --- Cours ------------------------------------------------------------------

  Future<CoursFiche> creer(DonneesCours d) async {
    verifierCours(titre: d.titre, dureeMinutes: d.dureeMinutes, prixCentimes: d.prixCentimes, places: d.places);
    final int id = await _db
        .into(_db.cours)
        .insert(
          CoursCompanion.insert(
            titre: d.titre.trim(),
            debutLe: d.debutLe,
            dureeMinutes: d.dureeMinutes,
            prixCentimes: d.prixCentimes,
            places: d.places,
            description: Value(nullSiVide(d.description)),
            lieu: Value(nullSiVide(d.lieu)),
            niveau: Value(d.niveau),
            materielInclus: Value(d.materielInclus),
            photoChemin: Value(d.photoChemin),
          ),
        );
    return _cours(id);
  }

  /// Modifie un cours. Les inscriptions déjà prises gardent leur prix. Le nombre de places ne peut pas passer
  /// sous le nombre de personnes confirmées.
  Future<CoursFiche> modifier(int id, DonneesCours d) {
    return _db.transaction(() async {
      await _cours(id);
      final int confirmes = await _compter(id, StatutInscription.confirmee);
      verifierCours(
        titre: d.titre,
        dureeMinutes: d.dureeMinutes,
        prixCentimes: d.prixCentimes,
        places: d.places,
        confirmes: confirmes,
      );
      await (_db.update(_db.cours)..where((t) => t.id.equals(id))).write(
        CoursCompanion(
          titre: Value(d.titre.trim()),
          description: Value(nullSiVide(d.description)),
          debutLe: Value(d.debutLe),
          dureeMinutes: Value(d.dureeMinutes),
          lieu: Value(nullSiVide(d.lieu)),
          prixCentimes: Value(d.prixCentimes),
          places: Value(d.places),
          niveau: Value(d.niveau),
          materielInclus: Value(d.materielInclus),
          photoChemin: Value(d.photoChemin),
          modifieLe: Value(DateTime.now()),
        ),
      );
      return _cours(id);
    });
  }

  /// Annule le cours. Les inscriptions restent telles quelles (à traiter une par une : annuler, rembourser ou non).
  Future<void> annulerCours(int id) async {
    final CoursFiche cours = await _cours(id);
    if (cours.statut == StatutCours.annule) throw const DonneeInvalide('Ce cours est déjà annulé.');
    await _changerStatut(id, StatutCours.annule);
  }

  /// Remet un cours annulé « prévu ». Les inscriptions annulées ne reviennent pas.
  Future<void> retablirCours(int id) async {
    final CoursFiche cours = await _cours(id);
    if (cours.statut != StatutCours.annule) throw const DonneeInvalide('Ce cours n’est pas annulé.');
    await _changerStatut(id, StatutCours.planifie);
  }

  /// Archive un cours terminé ou annulé (il quitte la liste « À venir » et « Passés »).
  Future<void> archiver(int id, {DateTime? maintenant}) async {
    final CoursFiche cours = await _cours(id);
    final String? refus = refusArchivage(
      statut: cours.statut,
      termine: coursTermine(cours.debutLe, cours.dureeMinutes, maintenant ?? DateTime.now()),
    );
    if (refus != null) throw DonneeInvalide(refus);
    await _marquerArchive(id, DateTime.now());
  }

  Future<void> restaurer(int id) async {
    await _cours(id);
    await _marquerArchive(id, null);
  }

  Future<CoursFiche?> obtenir(int id) =>
      (_db.select(_db.cours)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- Inscriptions -----------------------------------------------------------

  /// Inscrit [clientId] au cours [coursId].
  ///
  /// - S'il reste une place : l'inscription est **confirmée** et une vente est créée au [prixCentimes] convenu
  ///   (le prix du cours par défaut), avec le [paiement] éventuel (sans paiement : vente impayée).
  /// - Sinon : la personne va en **liste d'attente**, sans vente ni paiement (ils viennent à la confirmation).
  ///
  /// Une personne dont l'inscription a été annulée peut se réinscrire. Lance [DonneeInvalide] ou
  /// [ElementIntrouvable] (message en français) ; rien n'est alors enregistré.
  Future<ResultatInscription> inscrire({
    required int coursId,
    required int clientId,
    int? prixCentimes,
    PaiementSaisi? paiement,
    String? notes,
    DateTime? date,
  }) {
    return _db.transaction(() async {
      final CoursFiche cours = await _cours(coursId);
      final String? refus = refusInscription(statut: cours.statut, archive: cours.archiveLe != null);
      if (refus != null) throw DonneeInvalide(refus);
      await _controlerClient(clientId);

      final int prix = prixCentimes ?? cours.prixCentimes;
      if (prix < 0) throw const DonneeInvalide('Le prix ne peut pas être négatif.');

      final Inscription? existante = await _inscriptionDe(coursId, clientId);
      if (existante != null && existante.statut != StatutInscription.annulee) {
        throw DonneeInvalide(
          existante.statut == StatutInscription.confirmee
              ? 'Cette personne est déjà inscrite à ce cours.'
              : 'Cette personne est déjà sur la liste d’attente de ce cours.',
        );
      }

      final int confirmes = await _compter(coursId, StatutInscription.confirmee);
      final StatutInscription statut = statutNouvelleInscription(
        placesRestantes(places: cours.places, confirmes: confirmes),
      );
      if (statut == StatutInscription.listeAttente && paiement != null) {
        throw const DonneeInvalide(
          'Le cours est complet : la personne passe en liste d’attente, sans paiement pour le moment.',
        );
      }

      final Vente? vente = statut == StatutInscription.confirmee
          ? await _creerVente(cours: cours, clientId: clientId, prixCentimes: prix, paiement: paiement, date: date)
          : null;

      final DateTime quand = date ?? DateTime.now();
      final int id;
      if (existante == null) {
        id = await _db
            .into(_db.inscriptionsCours)
            .insert(
              InscriptionsCoursCompanion.insert(
                coursId: coursId,
                clientId: clientId,
                prixCentimes: prix,
                statut: Value(statut),
                dateInscription: Value(quand),
                venteId: Value(vente?.id),
                notes: Value(nullSiVide(notes)),
              ),
            );
      } else {
        id = existante.id;
        await (_db.update(_db.inscriptionsCours)..where((t) => t.id.equals(id))).write(
          InscriptionsCoursCompanion(
            statut: Value(statut),
            dateInscription: Value(quand),
            prixCentimes: Value(prix),
            venteId: Value(vente?.id),
            notes: Value(nullSiVide(notes)),
            modifieLe: Value(DateTime.now()),
          ),
        );
      }
      return ResultatInscription(inscription: await _inscription(id), vente: vente);
    });
  }

  /// Confirme la première personne de la liste d'attente, quand une place est libre : l'inscription devient
  /// « confirmée » et la vente est créée (au prix convenu, avec le [paiement] éventuel).
  Future<ResultatInscription> confirmer(int inscriptionId, {PaiementSaisi? paiement, DateTime? date}) {
    return _db.transaction(() async {
      final Inscription inscription = await _inscription(inscriptionId);
      final CoursFiche cours = await _cours(inscription.coursId);
      final List<Inscription> attente = await _inscriptions(cours.id, StatutInscription.listeAttente);
      final int confirmes = await _compter(cours.id, StatutInscription.confirmee);

      final String? refus = refusConfirmation(
        statutInscription: inscription.statut,
        statutCours: cours.statut,
        archive: cours.archiveLe != null,
        placesLibres: placesRestantes(places: cours.places, confirmes: confirmes),
        estPremiere: premierEnAttente(<EnAttente>[
              for (final Inscription i in attente)
                EnAttente(inscriptionId: i.id, dateInscription: i.dateInscription),
            ]) ==
            inscription.id,
      );
      if (refus != null) throw DonneeInvalide(refus);
      await _controlerClient(inscription.clientId);

      final Vente vente = await _creerVente(
        cours: cours,
        clientId: inscription.clientId,
        prixCentimes: inscription.prixCentimes,
        paiement: paiement,
        date: date,
      );
      await (_db.update(_db.inscriptionsCours)..where((t) => t.id.equals(inscriptionId))).write(
        InscriptionsCoursCompanion(
          statut: const Value(StatutInscription.confirmee),
          venteId: Value(vente.id),
          modifieLe: Value(DateTime.now()),
        ),
      );
      return ResultatInscription(inscription: await _inscription(inscriptionId), vente: vente);
    });
  }

  /// Annule une inscription (confirmée ou en attente). Une place confirmée qui se libère n'est donnée à personne
  /// automatiquement : on confirme soi-même la première personne en attente.
  ///
  /// Si l'inscription a une vente : elle est annulée aussi, et le net encaissé est remboursé, sauf si
  /// [rembourser] est faux **et** que de l'argent a été reçu : la vente et le paiement restent alors tels quels
  /// (le solde éventuel reste dû, la vente peut être annulée plus tard depuis son écran).
  Future<void> annulerInscription(int inscriptionId, {bool rembourser = true}) {
    return _db.transaction(() async {
      final Inscription inscription = await _inscription(inscriptionId);
      if (!peutAnnulerInscription(inscription.statut)) {
        throw const DonneeInvalide('Cette inscription est déjà annulée.');
      }
      final int? venteId = inscription.venteId;
      if (venteId != null) {
        final Vente? vente = await _ventes.obtenir(venteId);
        if (vente != null && vente.statut == StatutVente.validee) {
          final int net = await _encaisse(venteId);
          if (net <= 0 || rembourser) await _ventes.annuler(venteId);
        }
      }
      await (_db.update(_db.inscriptionsCours)..where((t) => t.id.equals(inscriptionId))).write(
        InscriptionsCoursCompanion(
          statut: const Value(StatutInscription.annulee),
          modifieLe: Value(DateTime.now()),
        ),
      );
    });
  }

  // --- Consultation -----------------------------------------------------------

  /// Les cours à afficher, avec leurs places. À venir : du plus proche au plus lointain ; passés et archivés : du
  /// plus récent au plus ancien. Un cours annulé reste dans « À venir » ou « Passés » selon sa date.
  Future<List<CoursResume>> lister({FiltreCours filtre = FiltreCours.aVenir, DateTime? maintenant}) async {
    final DateTime instant = maintenant ?? DateTime.now();
    final List<CoursFiche> tous = await _db.select(_db.cours).get();
    final List<CoursFiche> retenus = tous.where((CoursFiche c) {
      final bool termine = coursTermine(c.debutLe, c.dureeMinutes, instant);
      return switch (filtre) {
        FiltreCours.aVenir => c.archiveLe == null && !termine,
        FiltreCours.passes => c.archiveLe == null && termine,
        FiltreCours.archives => c.archiveLe != null,
      };
    }).toList()
      ..sort((CoursFiche a, CoursFiche b) {
        final int parDate = a.debutLe.compareTo(b.debutLe);
        final int ordre = parDate != 0 ? parDate : a.id.compareTo(b.id);
        return filtre == FiltreCours.aVenir ? ordre : -ordre;
      });

    final List<int> ids = retenus.map((CoursFiche c) => c.id).toList();
    final List<Inscription> inscriptions = ids.isEmpty
        ? <Inscription>[]
        : await (_db.select(_db.inscriptionsCours)..where((t) => t.coursId.isIn(ids))).get();
    final Map<int, int> confirmes = <int, int>{};
    final Map<int, int> enAttente = <int, int>{};
    for (final Inscription i in inscriptions) {
      if (i.statut == StatutInscription.confirmee) confirmes[i.coursId] = (confirmes[i.coursId] ?? 0) + 1;
      if (i.statut == StatutInscription.listeAttente) enAttente[i.coursId] = (enAttente[i.coursId] ?? 0) + 1;
    }
    return <CoursResume>[
      for (final CoursFiche c in retenus)
        CoursResume(cours: c, confirmes: confirmes[c.id] ?? 0, enAttente: enAttente[c.id] ?? 0),
    ];
  }

  /// Liste des cours, mise à jour automatiquement (cours créé ou modifié, inscription prise ou annulée).
  Stream<List<CoursResume>> observerListe({FiltreCours filtre = FiltreCours.aVenir}) => observerTables(
    _db,
    <ResultSetImplementation>{_db.cours, _db.inscriptionsCours},
    () => lister(filtre: filtre),
  );

  /// Fiche d'un cours avec ses inscrits (`null` s'il n'existe pas).
  Future<CoursDetail?> detail(int id) async {
    final CoursFiche? cours = await obtenir(id);
    if (cours == null) return null;

    final List<TypedResult> lignes =
        await (_db.select(_db.inscriptionsCours).join(<Join>[
                innerJoin(_db.clients, _db.clients.id.equalsExp(_db.inscriptionsCours.clientId)),
              ])
              ..where(_db.inscriptionsCours.coursId.equals(id))
              ..orderBy(<OrderingTerm>[
                OrderingTerm.asc(_db.inscriptionsCours.dateInscription),
                OrderingTerm.asc(_db.inscriptionsCours.id),
              ]))
            .get();

    final List<int> venteIds = <int>[
      for (final TypedResult l in lignes)
        if (l.readTable(_db.inscriptionsCours).venteId != null) l.readTable(_db.inscriptionsCours).venteId!,
    ];
    final Map<int, Vente> ventes = venteIds.isEmpty
        ? <int, Vente>{}
        : <int, Vente>{
            for (final Vente v in await (_db.select(_db.ventes)..where((t) => t.id.isIn(venteIds))).get()) v.id: v,
          };
    final Map<int, int> encaisse = <int, int>{};
    final Map<int, Facture> factures = <int, Facture>{};
    if (venteIds.isNotEmpty) {
      for (final Paiement p in await (_db.select(_db.paiements)..where((t) => t.venteId.isIn(venteIds))).get()) {
        encaisse[p.venteId] = (encaisse[p.venteId] ?? 0) + p.montantCentimes;
      }
      final List<Facture> emises =
          await (_db.select(_db.factures)..where(
                (t) => t.venteId.isIn(venteIds) & t.statut.equalsValue(StatutFacture.emise),
              ))
              .get();
      for (final Facture f in emises) {
        factures[f.venteId] = f;
      }
    }

    InscriptionDetail detailDe(TypedResult ligne, {int? rang}) {
      final Inscription inscription = ligne.readTable(_db.inscriptionsCours);
      final int? venteId = inscription.venteId;
      return InscriptionDetail(
        inscription: inscription,
        client: ligne.readTable(_db.clients),
        vente: venteId == null ? null : ventes[venteId],
        encaisseCentimes: venteId == null ? 0 : (encaisse[venteId] ?? 0),
        facture: venteId == null ? null : factures[venteId],
        rangAttente: rang,
      );
    }

    final List<InscriptionDetail> confirmees = <InscriptionDetail>[];
    final List<InscriptionDetail> annulees = <InscriptionDetail>[];
    final List<TypedResult> attente = <TypedResult>[];
    for (final TypedResult l in lignes) {
      switch (l.readTable(_db.inscriptionsCours).statut) {
        case StatutInscription.confirmee:
          confirmees.add(detailDe(l));
        case StatutInscription.annulee:
          annulees.add(detailDe(l));
        case StatutInscription.listeAttente:
          attente.add(l);
      }
    }
    // Les lignes sont déjà triées par date puis par identifiant : c'est l'ordre d'arrivée.
    final List<InscriptionDetail> enAttente = <InscriptionDetail>[
      for (int i = 0; i < attente.length; i++) detailDe(attente[i], rang: i + 1),
    ];
    return CoursDetail(cours: cours, confirmees: confirmees, enAttente: enAttente, annulees: annulees);
  }

  /// Fiche d'un cours, mise à jour automatiquement (inscriptions, paiements, factures, clients modifiés).
  Stream<CoursDetail?> observerDetail(int id) => observerTables(
    _db,
    <ResultSetImplementation>{
      _db.cours,
      _db.inscriptionsCours,
      _db.clients,
      _db.ventes,
      _db.paiements,
      _db.factures,
    },
    () => detail(id),
  );

  // --- Interne ----------------------------------------------------------------

  Future<CoursFiche> _cours(int id) async {
    final CoursFiche? cours = await obtenir(id);
    if (cours == null) throw const ElementIntrouvable('Ce cours n’existe plus.');
    return cours;
  }

  Future<Inscription> _inscription(int id) async {
    final Inscription? inscription = await (_db.select(
      _db.inscriptionsCours,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (inscription == null) throw const ElementIntrouvable('Cette inscription n’existe plus.');
    return inscription;
  }

  Future<Inscription?> _inscriptionDe(int coursId, int clientId) => (_db.select(
    _db.inscriptionsCours,
  )..where((t) => t.coursId.equals(coursId) & t.clientId.equals(clientId))).getSingleOrNull();

  Future<List<Inscription>> _inscriptions(int coursId, StatutInscription statut) => (_db.select(
    _db.inscriptionsCours,
  )..where((t) => t.coursId.equals(coursId) & t.statut.equalsValue(statut))).get();

  Future<int> _compter(int coursId, StatutInscription statut) async =>
      (await _inscriptions(coursId, statut)).length;

  Future<void> _controlerClient(int clientId) async {
    final Client? client = await (_db.select(_db.clients)..where((t) => t.id.equals(clientId))).getSingleOrNull();
    if (client == null) throw const ElementIntrouvable('Ce client n’existe plus.');
    if (client.archiveLe != null) {
      throw const DonneeInvalide('Ce client est archivé : restaurez sa fiche pour l’inscrire.');
    }
  }

  /// Net encaissé sur une vente : paiements moins remboursements.
  Future<int> _encaisse(int venteId) async {
    final List<Paiement> paiements = await (_db.select(
      _db.paiements,
    )..where((t) => t.venteId.equals(venteId))).get();
    return paiements.fold<int>(0, (int somme, Paiement p) => somme + p.montantCentimes);
  }

  /// La vente d'une inscription : une ligne « cours » (prestation, sans stock) au prix convenu.
  Future<Vente> _creerVente({
    required CoursFiche cours,
    required int clientId,
    required int prixCentimes,
    PaiementSaisi? paiement,
    DateTime? date,
  }) {
    final String? lieu = nullSiVide(cours.lieu);
    final Panier panier = const Panier().ajouter(
      coursId: cours.id,
      designation: 'Cours : ${cours.titre}',
      description:
          'Le ${formatDateCourte(cours.debutLe)} à ${formatHeure(cours.debutLe)} · '
          'durée ${formatDuree(cours.dureeMinutes)}${lieu == null ? '' : ' · $lieu'}',
      nature: NatureLigne.service,
      prixUnitaireCentimes: prixCentimes,
    );
    return _ventes.valider(
      clientId: clientId,
      panier: panier,
      paiement: paiement,
      notes: 'Inscription au cours « ${cours.titre} »',
      date: date,
    );
  }

  Future<void> _changerStatut(int id, StatutCours statut) async {
    await (_db.update(_db.cours)..where((t) => t.id.equals(id))).write(
      CoursCompanion(statut: Value(statut), modifieLe: Value(DateTime.now())),
    );
  }

  Future<void> _marquerArchive(int id, DateTime? date) async {
    await (_db.update(_db.cours)..where((t) => t.id.equals(id))).write(
      CoursCompanion(archiveLe: Value(date), modifieLe: Value(DateTime.now())),
    );
  }
}
