import '../../domain/agenda.dart';
import '../../domain/agenda_google.dart';
import '../drive/compte_google.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/parametres_repository.dart';
import 'client_agenda_google.dart';

/// Comment s'est passée une synchronisation (ou pourquoi elle n'a pas eu lieu).
enum IssueSynchro {
  /// Tout est à jour dans Google Agenda.
  reussie,

  /// Une partie seulement : des écritures ont été refusées ou n'ont pas pu être faites (retentées la prochaine fois).
  partielle,

  /// La synchronisation n'est pas activée : rien n'a été fait.
  desactivee,

  /// Cet appareil ne sait pas parler à Google Agenda.
  indisponible,

  /// La personne n'est pas connectée à Google (Réglages › Google Drive).
  nonConnecte,

  /// Le droit « Google Agenda » n'est pas accordé (ou plus) : il faut l'autoriser de nouveau.
  droitAbsent,

  /// La personne a fermé la fenêtre d'autorisation de Google.
  annulee,

  /// L'agenda mémorisé n'existe plus dans Google Agenda (il a été supprimé là-bas, ou n'est pas accessible depuis cet appareil).
  agendaIntrouvable,

  /// Une autre erreur (réseau, Google...) ; [BilanSynchro.message] l'explique.
  erreur,
}

/// Le bilan d'une synchronisation : [issue], le [resultat] chiffré quand elle a eu lieu, et un [message] lisible tel quel
/// quand il y a une erreur à expliquer.
class BilanSynchro {
  const BilanSynchro(this.issue, {this.resultat, this.message});

  final IssueSynchro issue;
  final ResultatSynchro? resultat;
  final String? message;

  /// Vrai si tout est à jour dans Google Agenda.
  bool get reussie => issue == IssueSynchro.reussie;
}

/// La synchronisation du calendrier vers Google Agenda, dans un seul sens : de l'application vers Google.
///
/// - L'application écrit dans **son propre agenda**, créé dans le compte Google de la personne (le droit demandé,
///   `calendar.app.created`, ne donne accès à aucun autre agenda).
/// - Chaque élément du calendrier devient un événement à identifiant stable : le modifier dans l'application modifie
///   l'événement, il n'en crée pas un second.
/// - Un élément qui disparaît de l'application (événement supprimé, cours annulé ou archivé, devis accepté ou expiré) n'est
///   **jamais supprimé** de Google Agenda : son événement est marqué « [Annulé] ». Seul [nettoyer], sur demande expresse de
///   la personne, supprime ces événements marqués.
/// - Ce qui est modifié à la main dans Google Agenda est remplacé à la prochaine synchronisation.
class ServiceAgendaGoogle {
  ServiceAgendaGoogle({
    required AgendaRepository agenda,
    required ParametresRepository parametres,
    required CompteGoogle compte,
    ClientAgendaGoogle? client,
    DateTime Function()? horloge,
  }) : _agenda = agenda,
       _parametres = parametres,
       _compte = compte,
       // `CompteAvecAgenda` est une interface à part : un simple test de type ne « promeut » pas le compte.
       _droit = compte is CompteAvecAgenda ? compte as CompteAvecAgenda : null,
       _client = client,
       _horloge = horloge ?? DateTime.now;

  final AgendaRepository _agenda;
  final ParametresRepository _parametres;
  final CompteGoogle _compte;
  final CompteAvecAgenda? _droit;
  final ClientAgendaGoogle? _client;
  final DateTime Function() _horloge;

  Future<BilanSynchro>? _enCours;

  /// Après autant d'échecs de suite, la synchronisation s'arrête (inutile d'insister si Google ou le réseau ne répond plus).
  static const int echecsConsecutifsMax = 3;

  /// Vrai si cet appareil sait parler à Google Agenda.
  bool get disponible => _droit != null && _client != null;

  /// Le droit « Google Agenda » est-il accordé en ce moment ? (Sans rien demander ni afficher.)
  Future<bool> droitAccorde() async {
    final CompteAvecAgenda? droit = _droit;
    if (droit == null) return false;
    try {
      return await _compte.restaurer() != null && await droit.agendaAutorise();
    } catch (_) {
      return false;
    }
  }

  /// Active la synchronisation : s'assure que la personne est connectée à Google, lui fait accorder le droit « Google
  /// Agenda » s'il ne l'est pas, mémorise le choix, puis lance une première synchronisation (qui crée l'agenda).
  Future<BilanSynchro> activer() async {
    final CompteAvecAgenda? droit = _droit;
    if (droit == null || _client == null) return const BilanSynchro(IssueSynchro.indisponible);
    try {
      if (await _compte.restaurer() == null) return const BilanSynchro(IssueSynchro.nonConnecte);
      if (!await droit.agendaAutorise()) await droit.autoriserAgenda();
    } on ErreurDrive catch (erreur) {
      if (erreur.annulee) return const BilanSynchro(IssueSynchro.annulee);
      return BilanSynchro(IssueSynchro.droitAbsent, message: erreur.message);
    } catch (erreur) {
      return BilanSynchro(IssueSynchro.erreur, message: 'L’autorisation de Google Agenda a échoué : $erreur');
    }
    await _parametres.enregistrerAgendaGoogle(actif: true);
    return synchroniser();
  }

  /// Désactive la synchronisation. Ce qui est déjà dans Google Agenda y reste (l'application n'y supprime rien), et l'agenda
  /// mémorisé est gardé : réactiver reprend le même agenda, sans doublon.
  Future<void> desactiver() => _parametres.enregistrerAgendaGoogle(actif: false);

  /// L'agenda mémorisé n'existe plus : l'oublie, en crée un autre et y envoie tout. N'est appelé que sur demande de la personne
  /// (elle l'a peut-être supprimé exprès).
  Future<BilanSynchro> recreerAgenda() async {
    await _parametres.enregistrerAgendaGoogle(oublierCalendrier: true);
    return synchroniser();
  }

  /// Envoie le calendrier vers Google Agenda. Ne lance jamais d'erreur : tout est dans le [BilanSynchro]. Deux demandes en
  /// même temps ne font qu'une synchronisation (elles partagent le même bilan). Sans effet si la synchronisation n'est pas
  /// activée.
  Future<BilanSynchro> synchroniser() => _enCours ??= _synchroniser().whenComplete(() => _enCours = null);

  Future<BilanSynchro> _synchroniser() async {
    final CompteAvecAgenda? droit = _droit;
    final ClientAgendaGoogle? client = _client;
    if (droit == null || client == null) return const BilanSynchro(IssueSynchro.indisponible);
    try {
      final ({bool actif, String? calendrier}) reglage = await _parametres.lireAgendaGoogle();
      if (!reglage.actif) return const BilanSynchro(IssueSynchro.desactivee);
      if (await _compte.restaurer() == null) return const BilanSynchro(IssueSynchro.nonConnecte);
      if (!await droit.agendaAutorise()) return const BilanSynchro(IssueSynchro.droitAbsent);

      String? calendrier = reglage.calendrier;
      if (calendrier == null) {
        calendrier = await client.creerCalendrier(nom: nomAgendaGoogle, fuseau: fuseauAgendaGoogle);
        await _parametres.enregistrerAgendaGoogle(calendrier: calendrier);
      }

      final DateTime maintenant = _horloge();
      final ({DateTime debut, DateTime fin}) fenetre = fenetreSynchro(maintenant);
      final FiltresAgenda filtres = ParametresRepository.filtresAgendaDe(await _parametres.lire());
      final List<EntreeAgenda> entrees = await _agenda.entrees(fenetre.debut, fenetre.fin, filtres: filtres, maintenant: maintenant);
      final List<EvenementGoogle> existants = await client.lister(calendrier, debut: fenetre.debut, fin: fenetre.fin);
      final PlanSynchro plan = planifierSynchro(
        souhaites: evenementsDepuisEntrees(entrees),
        existants: existants,
        filtres: filtres,
      );

      int crees = 0;
      int modifies = 0;
      int annules = 0;
      final String agendaCible = calendrier;
      final ({int echecs, String? message}) ecritures = await _executer(<Future<void> Function()>[
        for (final EvenementGoogle e in plan.aCreer)
          () async {
            await client.creer(agendaCible, e);
            crees++;
          },
        for (final EvenementGoogle e in plan.aRemplacer)
          () async {
            await client.remplacer(agendaCible, e);
            modifies++;
          },
        for (final EvenementGoogle e in plan.aAnnuler)
          () async {
            await client.remplacer(agendaCible, e);
            annules++;
          },
      ]);

      final ResultatSynchro resultat = ResultatSynchro(
        quand: _horloge(),
        crees: crees,
        modifies: modifies,
        annules: annules,
        inchanges: plan.inchanges,
        echecs: ecritures.echecs,
      );
      return BilanSynchro(
        resultat.complet ? IssueSynchro.reussie : IssueSynchro.partielle,
        resultat: resultat,
        message: ecritures.message,
      );
    } on CalendrierIntrouvable {
      return const BilanSynchro(IssueSynchro.agendaIntrouvable);
    } on ErreurDrive catch (erreur) {
      if (erreur.autorisationAExpire) return BilanSynchro(IssueSynchro.droitAbsent, message: erreur.message);
      return BilanSynchro(IssueSynchro.erreur, message: erreur.message);
    } catch (erreur) {
      return BilanSynchro(IssueSynchro.erreur, message: 'La synchronisation a échoué : $erreur');
    }
  }

  /// Fait les [actions] l'une après l'autre. Une écriture refusée est comptée en échec et on continue ; après
  /// [echecsConsecutifsMax] échecs de suite, on s'arrête (les actions restantes sont comptées en échec : elles seront
  /// retentées à la prochaine synchronisation). Une autorisation perdue ([ErreurDrive.autorisationAExpire]) ou un agenda
  /// disparu ([CalendrierIntrouvable]) interrompt tout.
  Future<({int echecs, String? message})> _executer(List<Future<void> Function()> actions) async {
    int echecs = 0;
    int deSuite = 0;
    String? message;
    for (int i = 0; i < actions.length; i++) {
      try {
        await actions[i]();
        deSuite = 0;
      } on ErreurDrive catch (erreur) {
        if (erreur.autorisationAExpire) rethrow;
        echecs++;
        deSuite++;
        message ??= erreur.message;
        if (deSuite >= echecsConsecutifsMax) {
          echecs += actions.length - i - 1;
          break;
        }
      }
    }
    return (echecs: echecs, message: message);
  }

  // --- Nettoyage, sur demande ----------------------------------------------------

  /// L'agenda Google prêt à servir (connecté, droit accordé, agenda créé), sinon une [ErreurDrive] lisible.
  Future<String> _agendaPret() async {
    final CompteAvecAgenda? droit = _droit;
    if (droit == null || _client == null) {
      throw const ErreurDrive('Google Agenda n’est pas disponible sur cet appareil.');
    }
    if (await _compte.restaurer() == null) {
      throw const ErreurDrive('Connectez-vous d’abord à Google (Réglages › Google Drive).');
    }
    if (!await droit.agendaAutorise()) {
      throw const ErreurDrive(
        'Le droit « Google Agenda » n’est pas accordé. Activez la synchronisation pour l’autoriser.',
        autorisationAExpire: true,
      );
    }
    final String? calendrier = (await _parametres.lireAgendaGoogle()).calendrier;
    if (calendrier == null) throw const ErreurDrive('Aucun agenda Google n’a encore été créé : il n’y a rien à nettoyer.');
    return calendrier;
  }

  Future<T> _garde<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CalendrierIntrouvable {
      throw const ErreurDrive(
        'L’agenda Google est introuvable : il a peut-être été supprimé dans Google Agenda, ou n’est pas accessible depuis cet appareil.',
      );
    }
  }

  /// Les événements de l'agenda Google marqués « [Annulé] » (tous, sans limite de date), pour que la personne voie ce
  /// qu'un nettoyage supprimerait. Lève une [ErreurDrive] lisible si Google ne répond pas.
  Future<List<EvenementGoogle>> evenementsAnnules() => _garde(() async {
    final String calendrier = await _agendaPret();
    final List<EvenementGoogle> tous = await _client!.lister(calendrier);
    return tous.where((EvenementGoogle e) => e.estAnnule).toList();
  });

  /// **Supprime** de Google Agenda les événements marqués « [Annulé] » : seulement quand la personne l'a demandé et confirmé.
  /// Rien n'est supprimé dans l'application. Rend le nombre d'événements supprimés et d'échecs.
  Future<({int supprimes, int echecs})> nettoyer() => _garde(() async {
    final String calendrier = await _agendaPret();
    final ClientAgendaGoogle client = _client!;
    final List<EvenementGoogle> annules = (await client.lister(calendrier)).where((EvenementGoogle e) => e.estAnnule).toList();
    int supprimes = 0;
    final ({int echecs, String? message}) fait = await _executer(<Future<void> Function()>[
      for (final EvenementGoogle e in annules)
        () async {
          await client.supprimer(calendrier, e.id);
          supprimes++;
        },
    ]);
    return (supprimes: supprimes, echecs: fait.echecs);
  });
}
