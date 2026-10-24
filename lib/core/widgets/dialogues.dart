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
///
/// [margeBas] relève le message au-dessus d'une barre posée en bas du contenu d'un onglet (la barre du
/// panier de l'onglet Vente) : les onglets sont dans le Scaffold de l'accueil, c'est lui qui affiche le
/// message, tout en bas, et il recouvrirait cette barre pendant quelques secondes.
void afficherMessage(BuildContext context, String message, {double margeBas = 0}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: margeBas > 0 ? SnackBarBehavior.floating : null,
        margin: margeBas > 0 ? EdgeInsets.fromLTRB(16, 0, 16, margeBas) : null,
      ),
    );
}

/// Message à montrer pour une erreur : celui de l'erreur « métier » telle quelle,
/// sinon une phrase générale (le détail technique n'a pas à être montré).
String messageErreur(Object erreur) {
  if (erreur is ErreurMetier) return erreur.message;
  return 'Une erreur est survenue. Réessayez, et si le problème continue, redémarrez l’application.';
}
