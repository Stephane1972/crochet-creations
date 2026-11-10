import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/stockage/selecteur_piece_jointe.dart';
import '../../domain/enums.dart';
import '../../domain/pieces_jointes.dart';

/// Une pièce jointe telle qu'on l'affiche dans la note : déjà enregistrée ([id] renseigné) ou tout juste ajoutée
/// (pas encore enregistrée avec la note).
class PieceAffichee {
  const PieceAffichee({
    required this.nomFichier,
    required this.nomAffiche,
    required this.type,
    required this.octets,
    this.id,
  });

  /// Nom du fichier rangé dans le téléphone.
  final String nomFichier;

  /// Nom que la personne reconnaît.
  final String nomAffiche;
  final TypePieceJointe type;
  final int octets;

  /// Identifiant en base ; `null` tant que la note n'est pas enregistrée.
  final int? id;
}

/// Les pièces jointes dans le formulaire d'une note : la liste, « Ajouter une pièce jointe » et les limites.
///
/// Ne fait rien elle-même : l'écran de la note range les fichiers, ouvre et retire (voir `NoteFormScreen`).
class SectionPiecesJointes extends StatelessWidget {
  const SectionPiecesJointes({
    super.key,
    required this.pieces,
    required this.fichierDe,
    required this.occupe,
    required this.onAjouter,
    required this.onOuvrir,
    required this.onRetirer,
  });

  final List<PieceAffichee> pieces;

  /// Le fichier d'une pièce, pour en afficher l'aperçu.
  final File Function(PieceAffichee piece) fichierDe;

  /// Un fichier est en cours de copie : on attend avant d'en ajouter un autre.
  final bool occupe;

  final VoidCallback onAjouter;
  final void Function(PieceAffichee piece) onOuvrir;
  final void Function(PieceAffichee piece) onRetirer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? discret = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      key: const Key('pieces-jointes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          pieces.isEmpty ? 'Pièces jointes' : 'Pièces jointes (${pieces.length} sur $nombreMaxPiecesJointes)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final PieceAffichee piece in pieces)
          ListTile(
            key: Key('piece-jointe-${piece.nomFichier}'),
            contentPadding: EdgeInsets.zero,
            leading: _Apercu(piece: piece, fichier: fichierDe(piece)),
            title: Text(piece.nomAffiche, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${piece.type.libelle} · ${formaterTailleFichier(piece.octets)}'),
            trailing: IconButton(
              tooltip: 'Retirer cette pièce jointe',
              icon: const Icon(Icons.close),
              onPressed: () => onRetirer(piece),
            ),
            onTap: () => onOuvrir(piece),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('ajouter-piece-jointe'),
            onPressed: occupe ? null : onAjouter,
            icon: occupe
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(occupe ? 'Ajout en cours…' : 'Ajouter une pièce jointe'),
          ),
        ),
        const SizedBox(height: 6),
        Text(libelleLimitesPiecesJointes(), key: const Key('limites-pieces-jointes'), style: discret),
      ],
    );
  }
}

class _Apercu extends StatelessWidget {
  const _Apercu({required this.piece, required this.fichier});

  final PieceAffichee piece;
  final File fichier;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final IconData icone = switch (piece.type) {
      TypePieceJointe.photo => Icons.image_outlined,
      TypePieceJointe.video => Icons.videocam_outlined,
      TypePieceJointe.document => Icons.description_outlined,
    };
    final Widget generique = Icon(icone, color: scheme.onSecondaryContainer);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: scheme.secondaryContainer,
        alignment: Alignment.center,
        child: piece.type == TypePieceJointe.photo
            ? Image.file(
                fichier,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (BuildContext context, Object erreur, StackTrace? pile) => generique,
              )
            : generique,
      ),
    );
  }
}

/// Feuille du bas « Que voulez-vous joindre ? ». Retourne `null` si on la referme.
Future<SourcePieceJointe?> demanderSourcePieceJointe(BuildContext context) {
  return showModalBottomSheet<SourcePieceJointe>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(contexteFeuille).pop(SourcePieceJointe.photoAppareil),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir une photo dans la galerie'),
              onTap: () => Navigator.of(contexteFeuille).pop(SourcePieceJointe.photoGalerie),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Filmer une vidéo'),
              onTap: () => Navigator.of(contexteFeuille).pop(SourcePieceJointe.videoAppareil),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Choisir une vidéo dans la galerie'),
              onTap: () => Navigator.of(contexteFeuille).pop(SourcePieceJointe.videoGalerie),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Choisir un document (PDF, Word, tableur…)'),
              onTap: () => Navigator.of(contexteFeuille).pop(SourcePieceJointe.document),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                libelleLimitesPiecesJointes(),
                style: Theme.of(contexteFeuille).textTheme.bodySmall?.copyWith(
                  color: Theme.of(contexteFeuille).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Une photo jointe, en plein écran : on peut la pincer pour agrandir.
class PhotoJointeScreen extends StatelessWidget {
  const PhotoJointeScreen({super.key, required this.fichier, required this.titre});

  final File fichier;
  final String titre;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            fichier,
            errorBuilder: (BuildContext context, Object erreur, StackTrace? pile) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Cette photo est introuvable sur le téléphone.', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
