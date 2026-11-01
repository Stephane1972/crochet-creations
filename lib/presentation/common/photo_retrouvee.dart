import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Photo retrouvée au démarrage, après qu'Android a fermé l'application pendant la prise de vue (voir
/// `SelecteurPhoto.retrouverPhotoPerdue`) : chemin du fichier, `null` s'il n'y en a pas. Fournie par `main()`.
final photoRetrouveeInitialeProvider = Provider<String?>((ref) => null);

/// La photo retrouvée, tant qu'elle n'a pas été utilisée. La feuille de choix de photo (produit, cours, ticket de
/// dépense) propose alors « Utiliser la photo retrouvée » ; elle disparaît dès qu'elle est utilisée, remplacée par
/// une autre photo, ou si son fichier n'existe plus.
class PhotoRetrouveeNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(photoRetrouveeInitialeProvider);

  void oublier() => state = null;
}

final photoRetrouveeProvider =
    NotifierProvider<PhotoRetrouveeNotifier, String?>(PhotoRetrouveeNotifier.new);
