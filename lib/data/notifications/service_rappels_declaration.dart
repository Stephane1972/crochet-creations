import '../../domain/declaration.dart';
import '../repositories/parametres_repository.dart';
import 'planificateur_rappels.dart';

/// Ce qui se passe quand on active le rappel ou qu'on essaie une notification.
enum ResultatRappel {
  /// C'est fait.
  reussi,

  /// L'utilisatrice a refusé les notifications (ou les a bloquées dans les réglages de l'appareil).
  autorisationRefusee,

  /// Cet appareil ne sait pas afficher de notification.
  indisponible,
}

/// Le rappel de la déclaration des recettes : fait le lien entre le réglage (activé ou non) et les notifications
/// programmées dans l'appareil. Rien ne dépend d'Internet ni d'un serveur.
class ServiceRappelsDeclaration {
  ServiceRappelsDeclaration({
    required ParametresRepository parametres,
    required PlanificateurRappels planificateur,
    DateTime Function()? horloge,
  }) : _parametres = parametres,
       _planificateur = planificateur,
       _horloge = horloge ?? DateTime.now;

  final ParametresRepository _parametres;
  final PlanificateurRappels _planificateur;
  final DateTime Function() _horloge;

  /// Vrai si cet appareil sait afficher des notifications.
  bool get disponible => _planificateur.disponible;

  /// Les notifications sont-elles autorisées en ce moment ? (Sans rien demander.)
  Future<bool> notificationsAutorisees() => _planificateur.autorise();

  /// À l'ouverture de l'application : si le rappel est activé, reprogramme les mois à venir (l'horizon avance avec le
  /// temps, et les notifications reprises d'une sauvegarde ou d'un autre appareil sont reprogrammées ici). Rien à faire
  /// si le rappel est désactivé. Ne lance jamais d'erreur : un souci de notification ne doit pas gêner l'ouverture.
  Future<void> synchroniser() async {
    if (!disponible) return;
    try {
      if (!await _parametres.lireRappelDeclaration()) return;
      // Autorisation retirée depuis dans les réglages de l'appareil : on ne programme rien (l'écran l'explique).
      if (!await _planificateur.autorise()) return;
      await _planificateur.remplacer(prochainsRappelsDeclaration(_horloge()));
    } catch (_) {
      // Voir plus haut.
    }
  }

  /// Active le rappel : demande l'autorisation, programme les notifications, puis mémorise le choix. Si
  /// l'autorisation est refusée, rien n'est activé.
  Future<ResultatRappel> activer() async {
    if (!disponible) return ResultatRappel.indisponible;
    if (!await _planificateur.demanderAutorisation()) return ResultatRappel.autorisationRefusee;
    await _planificateur.remplacer(prochainsRappelsDeclaration(_horloge()));
    await _parametres.enregistrerRappelDeclaration(true);
    return ResultatRappel.reussi;
  }

  /// Désactive le rappel : annule les notifications programmées, puis mémorise le choix.
  Future<void> desactiver() async {
    if (disponible) await _planificateur.annuler();
    await _parametres.enregistrerRappelDeclaration(false);
  }

  /// Affiche une notification tout de suite pour vérifier qu'elles fonctionnent sur cet appareil.
  Future<ResultatRappel> tester() async {
    if (!disponible) return ResultatRappel.indisponible;
    if (!await _planificateur.demanderAutorisation()) return ResultatRappel.autorisationRefusee;
    await _planificateur.afficherMaintenant(
      titre: titreRappelDeclaration,
      texte: 'Voici à quoi ressemblera le rappel de fin de mois. Tout fonctionne sur cet appareil.',
    );
    return ResultatRappel.reussi;
  }
}
