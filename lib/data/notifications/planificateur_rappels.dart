import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/app_constants.dart';
import '../../domain/declaration.dart';

/// Ce que l'appareil sait faire pour les rappels : demander l'autorisation d'afficher des notifications, en programmer
/// pour plus tard (même application fermée), les annuler, en afficher une tout de suite. Les tests le remplacent par un faux.
abstract class PlanificateurRappels {
  /// Vrai si cet appareil sait afficher des notifications (Android et Windows).
  bool get disponible;

  /// Vrai si les notifications sont autorisées en ce moment (sans rien demander).
  Future<bool> autorise();

  /// Demande l'autorisation d'afficher des notifications (Android 13 ou plus récent : une fenêtre du système). Renvoie
  /// vrai si elles sont autorisées.
  Future<bool> demanderAutorisation();

  /// Remplace tous les rappels de déclaration déjà programmés par [rappels].
  Future<void> remplacer(List<RappelDeclaration> rappels);

  /// Annule tous les rappels de déclaration programmés.
  Future<void> annuler();

  /// Affiche une notification tout de suite (bouton « Tester la notification »).
  Future<void> afficherMaintenant({required String titre, required String texte});
}

/// Le vrai planificateur : notifications locales d'Android (alarmes du système, rétablies après un redémarrage du
/// téléphone) et de Windows (notifications programmées du système, qui apparaissent même application fermée).
class PlanificateurRappelsSysteme implements PlanificateurRappels {
  PlanificateurRappelsSysteme({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _preparation;

  static const String _canal = 'declaration_recettes';

  /// Identifiant de la notification d'essai : hors de la plage des vrais rappels, pour ne jamais être annulée avec eux.
  static const int _identifiantEssai = 1;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _canal,
      'Rappel de déclaration',
      channelDescription: 'Rappel de fin de mois pour déclarer vos recettes.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );

  @override
  bool get disponible =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows);

  /// Prépare le système de notifications, une seule fois (et de nouveau au prochain appel si elle a échoué).
  Future<void> _preparer() {
    final Future<void> preparation = _preparation ??= _plugin
        .initialize(
          settings: const InitializationSettings(
            // L'icône de l'application (celle du lanceur).
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            windows: WindowsInitializationSettings(
              appName: AppConstants.nomApplication,
              appUserModelId: 'FrCrochetCreations.UnPtitCrochetDansLesStocks.Rappels',
              guid: '8d3f6a52-1c7e-4b09-a5d2-4e6f1b9c7a30',
            ),
          ),
        )
        .then<void>((bool? _) {});
    preparation.catchError((Object _) {
      _preparation = null;
    });
    return preparation;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> autorise() async {
    if (!disponible) return false;
    await _preparer();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> demanderAutorisation() async {
    if (!disponible) return false;
    await _preparer();
    // Windows n'a pas de demande : les notifications se règlent dans les paramètres du système.
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> remplacer(List<RappelDeclaration> rappels) async {
    if (!disponible) return;
    await _preparer();
    await _annulerLesRappels();
    for (final RappelDeclaration rappel in rappels) {
      await _plugin.zonedSchedule(
        id: rappel.id,
        title: rappel.titre,
        body: rappel.texte,
        scheduledDate: _instant(rappel.quand),
        notificationDetails: _details,
        // « Inexact » : le système peut avancer ou retarder un peu l'heure (pas d'autorisation d'alarme exacte à demander).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> annuler() async {
    if (!disponible) return;
    await _preparer();
    await _annulerLesRappels();
  }

  @override
  Future<void> afficherMaintenant({required String titre, required String texte}) async {
    if (!disponible) return;
    await _preparer();
    await _plugin.show(id: _identifiantEssai, title: titre, body: texte, notificationDetails: _details);
  }

  /// Annule les notifications de déclaration encore en attente (et seulement elles).
  Future<void> _annulerLesRappels() async {
    final List<PendingNotificationRequest> enAttente = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest demande in enAttente) {
      if (estIdentifiantRappel(demande.id)) await _plugin.cancel(id: demande.id);
    }
  }

  /// L'instant (heure locale) en heure universelle : la notification est programmée à un instant précis, que le
  /// fuseau horaire de l'appareil change ou non d'ici là, et sans base de fuseaux horaires à embarquer.
  static tz.TZDateTime _instant(DateTime local) {
    final DateTime u = local.toUtc();
    return tz.TZDateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }
}
