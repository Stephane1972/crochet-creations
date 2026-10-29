import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_vues.dart';
import '../../data/repositories/cours_repository.dart';
import '../../data/repositories/cours_vues.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../clients/client_widgets.dart';
import '../ventes/recap_widgets.dart';
import '../ventes/saisie_paiement.dart';
import '../ventes/selecteur_client.dart';
import 'cours_providers.dart';
import 'cours_widgets.dart';

/// Inscription à un cours (écran 18).
///
/// - Sans [inscriptionId] : on inscrit quelqu'un. Il reste de la place → inscription confirmée, avec sa vente et
///   son paiement (payé, acompte ou plus tard). Le cours est complet → la personne va en liste d'attente, sans
///   paiement pour le moment.
/// - Avec [inscriptionId] : on **confirme** la première personne de la liste d'attente, quand une place est libre.
///   Son prix a été convenu à son arrivée ; le paiement se règle ici.
class CoursInscriptionScreen extends ConsumerStatefulWidget {
  const CoursInscriptionScreen({super.key, required this.coursId, this.inscriptionId});

  final int coursId;
  final int? inscriptionId;

  @override
  ConsumerState<CoursInscriptionScreen> createState() => _CoursInscriptionScreenState();
}

class _CoursInscriptionScreenState extends ConsumerState<CoursInscriptionScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final GlobalKey<SaisiePaiementState> _paiementCle = GlobalKey<SaisiePaiementState>();
  final TextEditingController _prix = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  Client? _client;
  bool _prixInitialise = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _confirmation => widget.inscriptionId != null;

  @override
  void dispose() {
    _prix.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Le prix saisi en centimes ; `null` tant qu'il est vide ou incorrect.
  int? get _prixCentimes => parseMontantEuros(_prix.text);

  InscriptionDetail? _personneEnAttente(CoursDetail detail) {
    for (final InscriptionDetail p in detail.enAttente) {
      if (p.inscription.id == widget.inscriptionId) return p;
    }
    return null;
  }

  Future<void> _enregistrer(CoursDetail detail, InscriptionDetail? attente) async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    final Client? client = _confirmation ? attente?.client : _client;
    if (client == null) {
      afficherMessage(context, 'Choisissez la personne à inscrire.');
      return;
    }
    final int prix = _confirmation ? attente!.inscription.prixCentimes : _prixCentimes!;

    // Le paiement n'a de sens que pour une personne qui prend une place maintenant.
    PaiementSaisi? paiement;
    if (_paiementAffiche(detail, prix)) {
      try {
        paiement = _paiementCle.currentState?.paiement(prix);
      } on ErreurMetier catch (erreur) {
        afficherMessage(context, erreur.message);
        return;
      }
    }

    setState(() => _enCours = true);
    try {
      final CoursRepository repo = ref.read(coursRepositoryProvider);
      final String nom = libelleClient(client);
      final String message;
      if (_confirmation) {
        await repo.confirmer(widget.inscriptionId!, paiement: paiement);
        message = 'Inscription de $nom confirmée.';
      } else {
        final ResultatInscription resultat = await repo.inscrire(
          coursId: widget.coursId,
          clientId: client.id,
          prixCentimes: prix,
          paiement: paiement,
          notes: _notes.text,
        );
        message = resultat.inscription.statut == StatutInscription.listeAttente
            ? '$nom est sur la liste d’attente.'
            : 'Inscription de $nom enregistrée.';
      }
      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, message);
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Inscription impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  /// Vrai si la rubrique « Paiement » est utile : la personne prend une place (pas la liste d'attente) et le prix
  /// n'est pas nul.
  bool _paiementAffiche(CoursDetail detail, int? prix) {
    if (prix == null || prix <= 0) return false;
    return _confirmation || !detail.complet;
  }

  Future<void> _demanderAbandon() async {
    final bool abandonner = await confirmer(
      context,
      titre: 'Abandonner cette inscription ?',
      message: 'Ce que vous avez saisi ne sera pas enregistré.',
      libelleConfirmer: 'Abandonner',
      libelleAnnuler: 'Continuer la saisie',
    );
    if (!abandonner || !mounted) return;
    setState(() => _enregistre = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CoursDetail?> fiche = ref.watch(coursDetailProvider(widget.coursId));
    final String titre = _confirmation ? 'Confirmer l’inscription' : 'Inscription';

    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(titre)),
        body: fiche.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object erreur, StackTrace pile) => const _Message('Impossible de charger ce cours.'),
          data: (CoursDetail? detail) {
            if (detail == null) return const _Message('Ce cours n’existe plus.');
            return _corps(context, detail);
          },
        ),
      ),
    );
  }

  Widget _corps(BuildContext context, CoursDetail detail) {
    final InscriptionDetail? attente = _confirmation ? _personneEnAttente(detail) : null;
    if (_confirmation && attente == null) {
      return const _Message('Cette personne n’est plus sur la liste d’attente.');
    }

    // Prix proposé : celui du cours, ou celui convenu avec la personne en attente.
    if (!_prixInitialise) {
      _prixInitialise = true;
      final int prixDepart = attente?.inscription.prixCentimes ?? detail.cours.prixCentimes;
      _prix.text = formatMontantSaisie(prixDepart);
    }

    final String? refus = attente != null ? detail.refusConfirmationDe(attente) : detail.refusInscriptionCours;
    final int? prix = attente != null ? attente.inscription.prixCentimes : _prixCentimes;
    final bool listeAttente = !_confirmation && detail.complet;
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;

    final String libelleBouton = _confirmation
        ? 'Confirmer l’inscription'
        : listeAttente
        ? 'Mettre en liste d’attente'
        : 'Inscrire';

    return Form(
      key: _formulaire,
      onChanged: () {
        if (!_modifie) setState(() => _modifie = true);
      },
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                _EnTeteCours(detail: detail),
                const SizedBox(height: 16),
                if (refus != null) ...<Widget>[
                  Text(refus, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                if (attente != null)
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: PastilleClient(client: attente.client, taille: 40),
                      title: Text(libelleClient(attente.client)),
                      subtitle: Text('Sur la liste d’attente · n° ${attente.rangAttente ?? 1}'),
                    ),
                  )
                else
                  LigneChoixClient(
                    client: _client,
                    autoriserAucun: false,
                    titreAucun: 'Choisir la personne à inscrire',
                    sousTitreAucun: 'Appuyez pour ouvrir la liste des clients',
                    onChoisi: (Client? choisi) => setState(() {
                      _client = choisi;
                      _modifie = true;
                    }),
                  ),
                const SizedBox(height: 16),
                if (attente != null)
                  CarteRubrique(
                    titre: 'Prix convenu',
                    child: Text(
                      attente.inscription.prixCentimes == 0
                          ? 'Gratuit'
                          : formatEuros(attente.inscription.prixCentimes),
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                else
                  TextFormField(
                    controller: _prix,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (String _) => setState(() => _modifie = true),
                    decoration: InputDecoration(
                      labelText: 'Prix pour cette personne (€)',
                      helperText: 'Prix du cours : ${formatEuros(detail.cours.prixCentimes)}. Modifiable pour cette personne.',
                      helperMaxLines: 2,
                    ),
                    validator: (String? v) => validerMontantObligatoire(v, 'Indiquez le prix (0 si c’est gratuit).'),
                  ),
                const SizedBox(height: 16),
                if (_paiementAffiche(detail, prix))
                  SaisiePaiement(
                    key: _paiementCle,
                    phraseTout: 'L’inscription est réglée en totalité maintenant.',
                    phrasePlusTard: 'Rien n’est encaissé : l’inscription reste impayée jusqu’au règlement.',
                  )
                else
                  Text(
                    listeAttente
                        ? 'Le cours est complet : la personne passe en liste d’attente, sans paiement pour le moment. '
                              'Vous la confirmerez quand une place se libérera.'
                        : 'Ce cours est gratuit pour cette personne : rien à encaisser.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: discret),
                  ),
                if (!_confirmation) ...<Widget>[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Notes (facultatif)'),
                    validator: (String? v) => validerLongueurMax(v, 1000, 'La note'),
                  ),
                ],
              ],
            ),
          ),
          Material(
            elevation: 6,
            color: theme.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_enCours || refus != null) ? null : () => _enregistrer(detail, attente),
                    icon: _enCours
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(libelleBouton),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rappel du cours concerné, en haut de l'écran.
class _EnTeteCours extends StatelessWidget {
  const _EnTeteCours({required this.detail});

  final CoursDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CoursFiche cours = detail.cours;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: ImageCours(chemin: cours.photoChemin, largeur: 48, hauteur: 48, rayon: 10),
        title: Text(cours.titre, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${quandCours(cours.debutLe)}\n'
          '${textePlaces(confirmes: detail.confirmees.length, places: cours.places)}',
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(texte, textAlign: TextAlign.center),
      ),
    );
  }
}
