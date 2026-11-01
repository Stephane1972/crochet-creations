import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/providers.dart';
import '../../data/stockage/selecteur_photo.dart';

/// Ce que l'utilisatrice veut faire d'une photo.
enum ChoixPhoto { appareil, galerie, retirer }

/// Feuille du bas « Prendre une photo / Choisir dans la galerie / Retirer la photo ».
/// [retirable] : proposer « Retirer la photo » (il y a déjà une photo). Retourne `null` si on referme la feuille.
Future<ChoixPhoto?> demanderChoixPhoto(BuildContext context, WidgetRef ref, {required bool retirable}) {
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

/// Prend ou choisit la photo demandée ([ChoixPhoto.appareil] ou [ChoixPhoto.galerie], pas « retirer »). Retourne le
/// chemin du fichier, ou `null` si la personne annule ou si la photo n'est pas utilisable (un message l'explique alors).
Future<String?> choisirFichierPhoto(BuildContext context, WidgetRef ref, ChoixPhoto choix) async {
  final SelecteurPhoto selecteur = ref.read(selecteurPhotoProvider);
  try {
    return await selecteur.choisir(choix == ChoixPhoto.appareil ? SourcePhoto.appareil : SourcePhoto.galerie);
  } catch (erreur, pile) {
    debugPrint('Photo impossible : $erreur\n$pile');
    if (context.mounted) {
      afficherMessage(
        context,
        'Impossible d’utiliser cette photo. Vérifiez que l’application a le droit '
        'd’accéder à l’appareil photo et aux photos.',
      );
    }
    return null;
  }
}
