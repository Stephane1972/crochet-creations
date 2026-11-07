import 'package:flutter/material.dart';

import '../../core/widgets/dialogue_nom.dart';
import '../../domain/lieux_vente.dart';

/// Boîte « nom de lieu de vente » : un champ, l'erreur éventuelle (nom vide, réservé, déjà pris...) affichée sous le
/// champ, et un bouton qui lance [enregistrer]. Retourne ce que [enregistrer] a retourné, ou `null` si on annule.
///
/// L'enregistrement se fait **dans** la boîte : un nom refusé la laisse ouverte, avec l'explication.
Future<T?> demanderNomLieu<T>(
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
    libelleChamp: 'Nom du lieu de vente',
    messageEchec: 'Le lieu n’a pas pu être enregistré. Réessayez.',
    enregistrer: enregistrer,
    erreurNom: erreurNomLieu,
    nettoyerNom: nettoyerNomLieu,
    longueurMax: longueurMaxNomLieu,
    nomInitial: nomInitial,
    aide: aide,
  );
}
