import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/agenda_repository.dart';
import '../../domain/agenda.dart';

/// Création et modification d'un événement du calendrier (un marché, un rendez-vous, une échéance à soi). Sans
/// [evenementId] : nouvel événement, au [jour] affiché (aujourd'hui si absent).
///
/// Un titre, un jour, « toute la journée » ou une heure de début (et de fin, facultative), et des précisions libres.
class EvenementFormScreen extends ConsumerStatefulWidget {
  const EvenementFormScreen({super.key, this.evenementId, this.jour});

  final int? evenementId;
  final DateTime? jour;

  @override
  ConsumerState<EvenementFormScreen> createState() => _EvenementFormScreenState();
}

class _EvenementFormScreenState extends ConsumerState<EvenementFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final TextEditingController _titre = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  late DateTime _jour;
  bool _journeeEntiere = true;
  TimeOfDay _debut = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _fin;

  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _termine = false;
  bool _enCours = false;

  bool get _creation => widget.evenementId == null;

  @override
  void initState() {
    super.initState();
    _jour = jourDe(widget.jour ?? ref.read(horlogeProvider)());
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    _titre.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final EvenementAgenda? evenement = await ref.read(agendaRepositoryProvider).obtenir(widget.evenementId!);
      if (!mounted) return;
      if (evenement == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      setState(() {
        _titre.text = evenement.titre;
        _notes.text = evenement.notes;
        _jour = jourDe(evenement.debutLe);
        _journeeEntiere = evenement.journeeEntiere;
        if (!evenement.journeeEntiere) {
          _debut = TimeOfDay.fromDateTime(evenement.debutLe);
          _fin = evenement.finLe == null ? null : TimeOfDay.fromDateTime(evenement.finLe!);
        }
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement de l’événement impossible : $erreur\n$pile');
      if (!mounted) return;
      setState(() {
        _erreurChargement = true;
        _chargement = false;
      });
    }
  }

  void _marquerModifie() {
    if (!_modifie) setState(() => _modifie = true);
  }

  // --- Date et heures ---------------------------------------------------------

  Future<void> _choisirDate() async {
    final DateTime aujourdhui = DateTime.now();
    final DateTime premier = DateTime(aujourdhui.year - 1);
    final DateTime dernier = DateTime(aujourdhui.year + 5, 12, 31);
    final DateTime initiale = _jour.isBefore(premier) ? premier : (_jour.isAfter(dernier) ? dernier : _jour);
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: premier,
      lastDate: dernier,
      helpText: 'Jour de l’événement',
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _jour = jourDe(choisie);
      _modifie = true;
    });
  }

  Future<TimeOfDay?> _demanderHeure(TimeOfDay initiale, String aide) => showTimePicker(
    context: context,
    initialTime: initiale,
    helpText: aide,
    builder: (BuildContext contexte, Widget? enfant) =>
        MediaQuery(data: MediaQuery.of(contexte).copyWith(alwaysUse24HourFormat: true), child: enfant!),
  );

  Future<void> _choisirDebut() async {
    final TimeOfDay? choisie = await _demanderHeure(_debut, 'Heure de début');
    if (choisie == null || !mounted) return;
    setState(() {
      _debut = choisie;
      _modifie = true;
    });
  }

  Future<void> _choisirFin() async {
    final TimeOfDay? choisie = await _demanderHeure(_fin ?? _debut, 'Heure de fin');
    if (choisie == null || !mounted) return;
    setState(() {
      _fin = choisie;
      _modifie = true;
    });
  }

  static String _heure(TimeOfDay t) => '${t.hour} h ${t.minute.toString().padLeft(2, '0')}';

  static Duration _duree(TimeOfDay t) => Duration(hours: t.hour, minutes: t.minute);

  // --- Enregistrement ---------------------------------------------------------

  DonneesEvenement _construireDonnees() => DonneesEvenement(
    titre: _titre.text,
    jour: _jour,
    journeeEntiere: _journeeEntiere,
    heureDebut: _journeeEntiere ? null : _duree(_debut),
    heureFin: _journeeEntiere || _fin == null ? null : _duree(_fin!),
    notes: _notes.text,
  );

  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final AgendaRepository repo = ref.read(agendaRepositoryProvider);
      final DonneesEvenement donnees = _construireDonnees();
      if (_creation) {
        await repo.creer(donnees);
      } else {
        await repo.modifier(widget.evenementId!, donnees);
      }
      if (!mounted) return;
      _termine = true;
      afficherMessage(context, _creation ? 'Événement ajouté.' : 'Modifications enregistrées.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Enregistrement de l’événement impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _supprimer() async {
    final bool confirme = await confirmer(
      context,
      titre: 'Supprimer cet événement ?',
      message: 'Il disparaîtra du calendrier de l’application. Cette action est définitive.',
      libelleConfirmer: 'Supprimer',
    );
    if (!confirme || !mounted) return;
    setState(() => _enCours = true);
    try {
      await ref.read(agendaRepositoryProvider).supprimer(widget.evenementId!);
      if (!mounted) return;
      _termine = true;
      afficherMessage(context, 'Événement supprimé.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Suppression de l’événement impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _demanderAbandon() async {
    final bool abandonner = await confirmer(
      context,
      titre: 'Abandonner les modifications ?',
      message: 'Ce que vous avez saisi ne sera pas enregistré.',
      libelleConfirmer: 'Abandonner',
      libelleAnnuler: 'Continuer la saisie',
    );
    if (!abandonner || !mounted) return;
    setState(() => _termine = true); // plus rien à protéger : on peut quitter
    Navigator.of(context).pop();
  }

  // --- Interface --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool utilisable = !_chargement && !_introuvable && !_erreurChargement;
    return PopScope(
      canPop: _termine || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouvel événement' : 'Modifier l’événement'),
          actions: <Widget>[
            if (utilisable)
              TextButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
          ],
        ),
        body: _corps(context),
      ),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_introuvable || _erreurChargement) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _introuvable ? 'Cet événement n’existe plus.' : 'Impossible de charger cet événement.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          TextFormField(
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Titre *'),
            validator: (String? v) =>
                validerObligatoire(v, 'Le titre est obligatoire.') ??
                validerLongueurMax(v, longueurMaxTitreEvenement, 'Le titre'),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _choisirDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Jour *', suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text('${formatDateLongue(_jour)} ${_jour.year}'),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Toute la journée'),
            value: _journeeEntiere,
            onChanged: (bool v) => setState(() {
              _journeeEntiere = v;
              _modifie = true;
            }),
          ),
          if (!_journeeEntiere) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    onTap: _choisirDebut,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Début', suffixIcon: Icon(Icons.schedule)),
                      child: Text(_heure(_debut)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _choisirFin,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fin (facultatif)',
                        suffixIcon: _fin == null
                            ? const Icon(Icons.schedule)
                            : IconButton(
                                tooltip: 'Retirer l’heure de fin',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _fin = null;
                                  _modifie = true;
                                }),
                              ),
                      ),
                      child: Text(_fin == null ? 'Aucune' : _heure(_fin!)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Précisions (lieu, matériel à prévoir...)', alignLabelWithHint: true),
            validator: (String? v) => validerLongueurMax(v, longueurMaxNotesEvenement, 'Les précisions'),
          ),
          if (!_creation) ...<Widget>[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _enCours ? null : _supprimer,
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Supprimer l’événement'),
            ),
          ],
        ],
      ),
    );
  }
}
