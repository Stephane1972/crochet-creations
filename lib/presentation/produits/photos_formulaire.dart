import '../../data/stockage/stockage_photos.dart';

/// Photo secondaire dans le formulaire : déjà enregistrée ([id] renseigné) ou ajoutée à l'instant.
class PhotoForm {
  const PhotoForm({this.id, required this.chemin});

  final int? id;
  final String chemin;
}

/// Suivi des photos pendant la saisie d'un produit.
///
/// Les photos choisies sont copiées tout de suite dans le dossier de l'application, mais ne sont
/// liées au produit qu'à l'enregistrement. Cette classe sait donc ce qu'il faut supprimer, et quand :
/// - une photo ajoutée puis retirée (ou abandonnée) disparaît immédiatement ;
/// - une photo déjà enregistrée que l'on retire ne disparaît qu'**après** l'enregistrement,
///   pour qu'un abandon du formulaire ne fasse rien perdre.
class PhotosFormulaire {
  PhotosFormulaire({required this.stockage, this.principale, Iterable<PhotoForm> secondaires = const <PhotoForm>[]})
    : secondaires = List<PhotoForm>.of(secondaires);

  final StockagePhotos stockage;

  /// Nom du fichier de la photo principale (`null` = aucune).
  String? principale;
  final List<PhotoForm> secondaires;

  final Set<String> _ajoutes = <String>{};
  final List<String> _aRetirer = <String>[];
  final List<int> _idsASupprimer = <int>[];

  /// Fichiers copiés dans cette session et pas encore liés à un produit enregistré.
  Set<String> get fichiersAjoutes => Set<String>.unmodifiable(_ajoutes);

  /// Identifiants des photos secondaires enregistrées que l'on retire.
  List<int> get idsASupprimer => List<int>.unmodifiable(_idsASupprimer);

  /// Photos secondaires nouvelles (à enregistrer avec le produit).
  List<String> get nouvellesSecondaires =>
      secondaires.where((PhotoForm p) => p.id == null).map((PhotoForm p) => p.chemin).toList();

  /// Remplace la photo principale par le fichier [source] (copié dans l'application),
  /// ou la retire si [source] est `null`.
  Future<void> remplacerPrincipale(String? source) async {
    final String? nouvelle = source == null ? null : await _copier(source);
    final String? ancienne = principale;
    principale = nouvelle;
    if (ancienne != null) await _abandonner(ancienne);
  }

  Future<void> ajouterSecondaire(String source) async {
    secondaires.add(PhotoForm(chemin: await _copier(source)));
  }

  Future<void> retirerSecondaire(PhotoForm photo) async {
    secondaires.remove(photo);
    if (photo.id != null) _idsASupprimer.add(photo.id!);
    await _abandonner(photo.chemin);
  }

  /// À appeler une fois le produit enregistré : les nouveaux fichiers appartiennent désormais
  /// au produit, et ceux qu'on a retirés peuvent être supprimés.
  Future<void> apresEnregistrement() async {
    _ajoutes.clear();
    _idsASupprimer.clear();
    final List<String> aSupprimer = List<String>.of(_aRetirer);
    _aRetirer.clear();
    for (final String chemin in aSupprimer) {
      await stockage.supprimer(chemin);
    }
  }

  /// À appeler si l'utilisatrice abandonne : les fichiers copiés pour rien sont supprimés.
  Future<void> abandonner() async {
    final List<String> aSupprimer = _ajoutes.toList();
    _ajoutes.clear();
    for (final String chemin in aSupprimer) {
      await stockage.supprimer(chemin);
    }
  }

  Future<String> _copier(String source) async {
    final String nom = await stockage.enregistrer(source);
    _ajoutes.add(nom);
    return nom;
  }

  Future<void> _abandonner(String chemin) async {
    if (_ajoutes.remove(chemin)) {
      await stockage.supprimer(chemin);
    } else {
      _aRetirer.add(chemin);
    }
  }
}
