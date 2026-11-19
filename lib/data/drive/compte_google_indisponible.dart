import 'compte_google.dart';

/// Le compte Google quand la connexion n'est pas disponible (Windows, pour l'instant).
///
/// Il ne fait **rien** et ne contacte personne : aucun paquet Google n'est appelé (celui d'Android n'existe pas sous
/// Windows). L'application reste ainsi entièrement utilisable : la personne n'est « jamais connectée », l'envoi
/// automatique vers Drive ne part donc jamais, et l'écran Google Drive explique que la connexion n'existe que sur Android.
class CompteGoogleIndisponible implements CompteGoogle {
  const CompteGoogleIndisponible();

  static const String message = 'Google Drive n’est pas encore disponible sous Windows : il l’est sur Android.';

  @override
  bool get configure => false;

  @override
  String get clientWeb => '';

  @override
  bool get clientWebEnregistre => false;

  @override
  bool get redemarrageNecessaire => false;

  @override
  Future<void> enregistrerClientWeb(String saisie) async => throw const ErreurDrive(message);

  @override
  Future<void> oublierClientWeb() async {}

  @override
  Future<ProfilGoogle?> restaurer() async => null;

  @override
  Future<ProfilGoogle> seConnecter() async => throw const ErreurDrive(message);

  @override
  Future<void> seDeconnecter() async {}

  @override
  Future<String> jetonAcces() async => throw const ErreurDrive(message);

  @override
  void invaliderJeton() {}
}
