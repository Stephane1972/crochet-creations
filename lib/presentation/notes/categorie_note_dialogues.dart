import 'package:flutter/material.dart';

import '../../core/widgets/dialogue_nom.dart';
import '../../domain/notes.dart';

/// Boîte « nom de catégorie de notes » : un champ, l'erreur éventuelle (nom vide, réservé, déjà pris...) affichée sous
/// le champ, et un bouton qui lance [enregistrer]. Retourne ce que [enregistrer] a retourné, ou `null` si on annule.
///
/// L'enregistrement se fait **dans** la boîte : un nom refusé la laisse ouverte, avec l'explication.
Future<T?> demanderNomCategorieNote<T>(
  BuildContext context, {
  required String titre,
  required String libelleValider,
  required Future<T> Function(String nom) enregistrer,
  String nomInitial = '',
  String? aide,
}) {
  return demanderNom<T>(
    context,
    titre: titre,
    libelleValider: libelleValider,
    libelleChamp: 'Nom de la catégorie',
    messageEchec: 'La catégorie n’a pas pu être enregistrée. Réessayez.',
    enregistrer: enregistrer,
    erreurNom: erreurNomCategorieNote,
    nettoyerNom: nettoyerNomCategorieNote,
    longueurMax: longueurMaxNomCategorieNote,
    nomInitial: nomInitial,
    aide: aide,
  );
}
