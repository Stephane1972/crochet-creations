import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/dialogues.dart';
import '../../domain/erreurs.dart';

/// Dit ce qui manque dans « Mon entreprise » pour établir une facture et propose d'ouvrir ce profil.
/// Rien n'a été créé à ce stade : aucun numéro de facture n'est consommé.
Future<void> proposerProfilComplet(BuildContext context, ProfilIncomplet manque) async {
  final bool ouvrir = await confirmer(
    context,
    titre: 'Informations manquantes',
    message: manque.message,
    libelleConfirmer: 'Ouvrir « Mon entreprise »',
    libelleAnnuler: 'Plus tard',
  );
  if (ouvrir && context.mounted) await Navigator.of(context).pushNamed(AppRoutes.monEntreprise);
}
