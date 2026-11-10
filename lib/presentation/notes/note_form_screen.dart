import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/stockage/ouvreur_piece_jointe.dart';
import '../../data/stockage/selecteur_piece_jointe.dart';
import '../../data/stockage/stockage_pieces_jointes.dart';
import '../../domain/enums.dart';
import '../../domain/notes.dart';
import '../../domain/pieces_jointes.dart';
import 'choix_categorie_note.dart';
import 'notes_providers.dart';
import 'pieces_jointes_section.dart';

enum _ActionNote { supprimer }

/// Création et modification d'une note. Sans [noteId] : nouvelle note.
///
/// Un titre (obligatoire), un texte (facultatif), une catégorie (facultative : « Sans catégorie ») et des pièces jointes
/// (photos, vidéos, documents : voir `pieces_jointes.dart` pour les limites).
/// Une note se supprime définitivement, avec ses pièces jointes, après confirmation.
///
/// Les pièces jointes ajoutées sont copiées dans le téléphone tout de suite, mais ne font partie de la note qu'à
/// « Enregistrer » ; celles qu'on retire ne sont effacées qu'à « Enregistrer » aussi. Si on abandonne, les copies
/// des pièces ajoutées sont effacées.
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

  /// Pièces jointes déjà enregistrées avec la note, celles qu'on a retirées (effacées à « Enregistrer »), et celles
  /// qu'on vient d'ajouter (rangées dans le téléphone, enregistrées avec la note à « Enregistrer »).
  List<PieceJointeNote> _piecesExistantes = <PieceJointeNote>[];
  final Set<int> _piecesRetirees = <int>{};
  final List<PieceRangee> _piecesAjoutees = <PieceRangee>[];
  bool _ajoutEnCours = false;
  bool _enregistree = false;
  late final StockagePiecesJointes _stockage;

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
    _stockage = ref.read(stockagePiecesJointesProvider);
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    // On quitte sans avoir enregistré : les copies des pièces ajoutées n'ont plus de raison d'être.
    if (!_enregistree && _piecesAjoutees.isNotEmpty) {
      unawaited(_stockage.supprimerTous(_piecesAjoutees.map((PieceRangee p) => p.nomFichier).toList()));
    }
    _titre.dispose();
    _contenu.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final NoteRepository repo = ref.read(noteRepositoryProvider);
      final Note? note = await repo.obtenir(widget.noteId!);
      final List<PieceJointeNote> pieces = note == null ? <PieceJointeNote>[] : await repo.listerPiecesJointes(note.id);
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
        _piecesExistantes = pieces;
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
        await repo.creer(
          titre: _titre.text,
          contenu: _contenu.text,
          categorieId: _categorieId,
          piecesJointes: _piecesAjoutees,
        );
      } else {
        await repo.modifier(
          widget.noteId!,
          titre: _titre.text,
          contenu: _contenu.text,
          categorieId: _categorieId,
          ajouts: _piecesAjoutees,
          retraits: _piecesRetirees,
        );
      }
      _enregistree = true; // les pièces ajoutées font maintenant partie de la note : on ne les efface plus

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

  // --- Pièces jointes ---------------------------------------------------------

  /// Les pièces jointes affichées : celles de la note (sauf les retirées), puis celles qu'on vient d'ajouter.
  List<PieceAffichee> get _pieces => <PieceAffichee>[
    for (final PieceJointeNote p in _piecesExistantes)
      if (!_piecesRetirees.contains(p.id))
        PieceAffichee(
          id: p.id,
          nomFichier: p.nomFichier,
          nomAffiche: p.nomAffiche,
          type: p.typeFichier,
          octets: p.octets,
        ),
    for (final PieceRangee p in _piecesAjoutees)
      PieceAffichee(nomFichier: p.nomFichier, nomAffiche: p.nomAffiche, type: p.type, octets: p.octets),
  ];

  Future<void> _ajouterPieceJointe() async {
    if (_ajoutEnCours || _enCours) return;
    final String? trop = erreurNombrePiecesJointes(_pieces.length + 1);
    if (trop != null) {
      afficherMessage(context, trop);
      return;
    }
    final SourcePieceJointe? source = await demanderSourcePieceJointe(context);
    if (source == null || !mounted) return;

    setState(() => _ajoutEnCours = true);
    try {
      final FichierChoisi? choisi = await ref.read(selecteurPieceJointeProvider).choisir(source);
      if (choisi == null) return;
      final PieceRangee rangee = await _stockage.enregistrer(choisi);
      if (!mounted) {
        await _stockage.supprimer(rangee.nomFichier);
        return;
      }
      setState(() {
        _piecesAjoutees.add(rangee);
        _modifie = true;
      });
    } catch (erreur, pile) {
      debugPrint('Ajout de la pièce jointe impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _ajoutEnCours = false);
    }
  }

  void _retirerPieceJointe(PieceAffichee piece) {
    setState(() {
      _modifie = true;
      if (piece.id != null) {
        // Déjà enregistrée : retirée de la liste, effacée seulement à « Enregistrer ».
        _piecesRetirees.add(piece.id!);
      } else {
        // Pas encore enregistrée : la copie n'a plus de raison d'être.
        _piecesAjoutees.removeWhere((PieceRangee p) => p.nomFichier == piece.nomFichier);
        unawaited(_stockage.supprimer(piece.nomFichier));
      }
    });
  }

  Future<void> _ouvrirPieceJointe(PieceAffichee piece) async {
    final File fichier = _stockage.fichier(piece.nomFichier);
    if (piece.type == TypePieceJointe.photo) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PhotoJointeScreen(fichier: fichier, titre: piece.nomAffiche),
        ),
      );
      return;
    }
    final ResultatOuverture resultat = await ref.read(ouvreurPieceJointeProvider).ouvrir(fichier);
    if (!mounted) return;
    switch (resultat) {
      case ResultatOuverture.ouvert:
        break;
      case ResultatOuverture.aucuneApplication:
        afficherMessage(context, 'Aucune application du téléphone ne sait ouvrir ce fichier.');
      case ResultatOuverture.introuvable:
        afficherMessage(context, 'Ce fichier est introuvable sur le téléphone.');
      case ResultatOuverture.echec:
        afficherMessage(context, 'Impossible d’ouvrir ce fichier.');
    }
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
          const SizedBox(height: 24),
          SectionPiecesJointes(
            pieces: _pieces,
            fichierDe: (PieceAffichee p) => _stockage.fichier(p.nomFichier),
            occupe: _ajoutEnCours,
            onAjouter: _ajouterPieceJointe,
            onOuvrir: _ouvrirPieceJointe,
            onRetirer: _retirerPieceJointe,
          ),
        ],
      ),
    );
  }
}
