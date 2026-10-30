import 'package:flutter/material.dart';

/// Ce que l'utilisatrice veut faire d'une photo.
enum ChoixPhoto { appareil, galerie, retirer }

/// Feuille du bas « Prendre une photo / Choisir dans la galerie / Retirer la photo ».
/// [retirable] : proposer « Retirer la photo » (il y a déjà une photo). Retourne `null` si on referme la feuille.
Future<ChoixPhoto?> demanderChoixPhoto(BuildContext context, {required bool retirable}) {
  return showModalBottomSheet<ChoixPhoto>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(contexteFeuille).pop(ChoixPhoto.appareil),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.of(contexteFeuille).pop(ChoixPhoto.galerie),
          ),
          if (retirable)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Retirer la photo'),
              onTap: () => Navigator.of(contexteFeuille).pop(ChoixPhoto.retirer),
            ),
        ],
      ),
    ),
  );
}
