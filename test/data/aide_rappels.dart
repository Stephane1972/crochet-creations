import 'package:crochet_creations/data/notifications/planificateur_rappels.dart';
import 'package:crochet_creations/domain/declaration.dart';

/// Faux planificateur de notifications, pour les tests : rien ne s'affiche, il note ce qu'on lui demande.
///
/// [autorisation] est l'état des notifications dans les réglages de l'appareil ; [reponseALaDemande] est ce que répond la
/// personne quand l'application demande l'autorisation (acceptée : l'état devient « autorisé »).
class FauxPlanificateurRappels implements PlanificateurRappels {
  FauxPlanificateurRappels({this.disponible = true, this.autorisation = true, this.reponseALaDemande = true});

  @override
  bool disponible;

  bool autorisation;
  bool reponseALaDemande;

  /// Les notifications actuellement programmées (le contenu du dernier `remplacer`, vidé par `annuler`).
  List<RappelDeclaration> programmes = <RappelDeclaration>[];

  /// Nombre d'appels à chacune des méthodes qui agissent.
  int demandes = 0;
  int remplacements = 0;
  int annulations = 0;

  /// Les notifications affichées tout de suite (bouton « Tester la notification »).
  final List<({String titre, String texte})> affichees = <({String titre, String texte})>[];

  /// Si défini, `remplacer` échoue avec cette erreur (le système de notifications ne répond pas).
  Object? erreurAuRemplacement;

  @override
  Future<bool> autorise() async => autorisation;

  @override
  Future<bool> demanderAutorisation() async {
    demandes++;
    if (!autorisation) autorisation = reponseALaDemande;
    return autorisation;
  }

  @override
  Future<void> remplacer(List<RappelDeclaration> rappels) async {
    final Object? erreur = erreurAuRemplacement;
    if (erreur != null) throw erreur;
    remplacements++;
    programmes = List<RappelDeclaration>.of(rappels);
  }

  @override
  Future<void> annuler() async {
    annulations++;
    programmes = <RappelDeclaration>[];
  }

  @override
  Future<void> afficherMaintenant({required String titre, required String texte}) async {
    affichees.add((titre: titre, texte: texte));
  }
}
