import 'package:flutter/material.dart';

import '../../domain/erreurs.dart';

/// Demande une confirmation avant une action importante. Retourne `true` si elle confirme.
Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String message,
  required String libelleConfirmer,
  String libelleAnnuler = 'Annuler',
}) async {
  final bool? resultat = await showDialog<bool>(
    context: context,
    builder: (BuildContext contexteDialogue) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(false),
          child: Text(libelleAnnuler),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(true),
          child: Text(libelleConfirmer),
        ),
      ],
    ),
  );
  return resultat ?? false;
}

/// Affiche un court message en bas de l'écran.
void afficherMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Message à montrer pour une erreur : celui de l'erreur « métier » telle quelle,
/// sinon une phrase générale (le détail technique n'a pas à être montré).
String messageErreur(Object erreur) {
  if (erreur is ErreurMetier) return erreur.message;
  return 'Une erreur est survenue. Réessayez, et si le problème continue, redémarrez l’application.';
}
