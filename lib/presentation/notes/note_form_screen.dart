import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/note_repository.dart';
import '../../domain/notes.dart';
import 'choix_categorie_note.dart';
import 'notes_providers.dart';

enum _ActionNote { supprimer }

/// Création et modification d'une note. Sans [noteId] : nouvelle note.
///
/// Un titre (obligatoire), un texte (facultatif) et une catégorie (facultative : « Sans catégorie »).
/// Une note se supprime définitivement, après confirmation.
class NoteFormScreen extends ConsumerStatefulWidget {
  const NoteFormScreen({super.key, this.noteId});

  final int? noteId;

  @override
  ConsumerState<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends ConsumerState<NoteFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _titre = TextEditingController();
  final TextEditingController _contenu = TextEditingController();

  int? _categorieId;

  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _termine = false;
  bool _enCours = false;

  bool get _creation => widget.noteId == null;

  @override
  void initState() {
    super.initState();
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    _titre.dispose();
    _contenu.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final Note? note = await ref.read(noteRepositoryProvider).obtenir(widget.noteId!);
      if (!mounted) return;
      if (note == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      setState(() {
        _titre.text = note.titre;
        _contenu.text = note.contenu;
        _categorieId = note.categorieId;
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement de la note impossible : $erreur\n$pile');
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

  // --- Enregistrement ---------------------------------------------------------

  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final NoteRepository repo = ref.read(noteRepositoryProvider);
      if (_creation) {
        await repo.creer(titre: _titre.text, contenu: _contenu.text, categorieId: _categorieId);
      } else {
        await repo.modifier(widget.noteId!, titre: _titre.text, contenu: _contenu.text, categorieId: _categorieId);
      }

      if (!mounted) return;
      _termine = true;
      afficherMessage(context, _creation ? 'Note enregistrée.' : 'Modifications enregistrées.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Enregistrement de la note impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _supprimer() async {
    if (_enCours) return;
    final bool oui = await confirmer(
      context,
      titre: 'Supprimer cette note ?',
      message: 'La note « ${nettoyerTitreNote(_titre.text)} » sera supprimée définitivement.',
      libelleConfirmer: 'Supprimer',
    );
    if (!oui || !mounted) return;
    setState(() => _enCours = true);
    try {
      await ref.read(noteRepositoryProvider).supprimer(widget.noteId!);
      if (!mounted) return;
      _termine = true; // plus rien à protéger : on peut quitter
      afficherMessage(context, 'Note supprimée.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Suppression de la note impossible : $erreur\n$pile');
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
    final bool chargee = !_chargement && !_introuvable && !_erreurChargement;
    return PopScope(
      canPop: _termine || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouvelle note' : 'Modifier la note'),
          actions: <Widget>[
            if (chargee)
              TextButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
            if (chargee && !_creation)
              PopupMenuButton<_ActionNote>(
                tooltip: 'Plus d’actions',
                onSelected: (_ActionNote action) {
                  switch (action) {
                    case _ActionNote.supprimer:
                      _supprimer();
                  }
                },
                itemBuilder: (BuildContext context) => const <PopupMenuEntry<_ActionNote>>[
                  PopupMenuItem<_ActionNote>(
                    value: _ActionNote.supprimer,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Supprimer la note'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
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
            _introuvable ? 'Cette note n’existe plus.' : 'Impossible de charger cette note.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final AsyncValue<List<CategorieNote>> categories = ref.watch(categoriesNoteProvider);

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
            validator: erreurTitreNote,
          ),
          const SizedBox(height: 12),
          LigneChoixCategorieNote(
            categorie: categorieNoteParId(categories.valueOrNull ?? const <CategorieNote>[], _categorieId),
            chargee: categories.hasValue || categories.hasError,
            onChoisie: (int? categorieId) => setState(() {
              _categorieId = categorieId;
              _modifie = true;
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contenu,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Texte', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }
}
