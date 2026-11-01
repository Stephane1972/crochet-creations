import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/providers.dart';
import '../../data/stockage/selecteur_photo.dart';
import 'photo_retrouvee.dart';

/// Ce que l'utilisatrice veut faire d'une photo.
enum ChoixPhoto { appareil, galerie, retirer, retrouvee }

/// Feuille du bas « Prendre une photo / Choisir dans la galerie / Retirer la photo ».
/// [retirable] : proposer « Retirer la photo » (il y a déjà une photo). Retourne `null` si on referme la feuille.
///
/// Si une photo a été retrouvée au démarrage (Android avait fermé l'application pendant la prise de vue) et que son
/// fichier existe encore, la feuille propose en premier « Utiliser la photo retrouvée ».
Future<ChoixPhoto?> demanderChoixPhoto(BuildContext context, WidgetRef ref, {required bool retirable}) {
  final String? retrouvee = ref.read(photoRetrouveeProvider);
  final bool proposerRetrouvee = retrouvee != null && File(retrouvee).existsSync();
  if (retrouvee != null && !proposerRetrouvee) ref.read(photoRetrouveeProvider.notifier).oublier();

  return showModalBottomSheet<ChoixPhoto>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (proposerRetrouvee)
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Utiliser la photo retrouvée'),
              subtitle: const Text('Prise juste avant la fermeture de l’application.'),
              onTap: () => Navigator.of(contexteFeuille).pop(ChoixPhoto.retrouvee),
            ),
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

/// Prend ou choisit la photo demandée ([ChoixPhoto.appareil], [ChoixPhoto.galerie] ou [ChoixPhoto.retrouvee], pas
/// « retirer »). Retourne le chemin du fichier, ou `null` si la personne annule ou si la photo n'est pas utilisable
/// (un message l'explique alors). La photo retrouvée est « consommée » : elle n'est plus proposée ensuite, pas plus
/// qu'après le choix d'une autre photo.
Future<String?> choisirFichierPhoto(BuildContext context, WidgetRef ref, ChoixPhoto choix) async {
  final PhotoRetrouveeNotifier retrouvee = ref.read(photoRetrouveeProvider.notifier);
  if (choix == ChoixPhoto.retrouvee) {
    final String? chemin = ref.read(photoRetrouveeProvider);
    retrouvee.oublier();
    return chemin;
  }
  final SelecteurPhoto selecteur = ref.read(selecteurPhotoProvider);
  try {
    final String? chemin = await selecteur.choisir(
      choix == ChoixPhoto.appareil ? SourcePhoto.appareil : SourcePhoto.galerie,
    );
    if (chemin != null) retrouvee.oublier();
    return chemin;
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
