import 'dart:convert';
import 'dart:io';

/// Ce que l'application garde, sur cet ordinateur, pour se connecter à Google : l'accès « application de bureau » saisi par
/// la personne (ID client et code secret) et, une fois connectée, son autorisation durable (jeton d'actualisation).
class ReglagesGoogleBureau {
  const ReglagesGoogleBureau({
    this.clientId = '',
    this.codeSecret = '',
    this.jetonActualisation,
    this.email = '',
    this.nom,
  });

  /// L'ID client de l'accès « application de bureau » (vide : aucun).
  final String clientId;

  /// Le code secret de cet accès (vide : aucun). Google le considère comme non confidentiel pour une application installée,
  /// mais il n'est jamais envoyé nulle part ailleurs qu'à Google, ni mis dans la sauvegarde.
  final String codeSecret;

  /// L'autorisation durable accordée par la personne (`null` : pas connectée).
  final String? jetonActualisation;

  /// Le compte connecté, pour l'afficher.
  final String email;
  final String? nom;

  ReglagesGoogleBureau copier({
    String? clientId,
    String? codeSecret,
    String? jetonActualisation,
    bool oublierJeton = false,
    String? email,
    String? nom,
  }) {
    return ReglagesGoogleBureau(
      clientId: clientId ?? this.clientId,
      codeSecret: codeSecret ?? this.codeSecret,
      jetonActualisation: oublierJeton ? null : (jetonActualisation ?? this.jetonActualisation),
      email: oublierJeton ? '' : (email ?? this.email),
      nom: oublierJeton ? null : (nom ?? this.nom),
    );
  }

  Map<String, Object?> versJson() => <String, Object?>{
    'clientId': clientId,
    'codeSecret': codeSecret,
    'jetonActualisation': jetonActualisation,
    'email': email,
    'nom': nom,
  };

  static ReglagesGoogleBureau depuisJson(Object? json) {
    if (json is! Map<String, Object?>) return const ReglagesGoogleBureau();
    String texte(String cle) => json[cle] is String ? json[cle]! as String : '';
    final String jeton = texte('jetonActualisation');
    final String nom = texte('nom');
    return ReglagesGoogleBureau(
      clientId: texte('clientId'),
      codeSecret: texte('codeSecret'),
      jetonActualisation: jeton.isEmpty ? null : jeton,
      email: texte('email'),
      nom: nom.isEmpty ? null : nom,
    );
  }
}

/// Le petit fichier des [ReglagesGoogleBureau], dans le dossier de données de l'utilisateur (hors de la base et des
/// sauvegardes : c'est un réglage de l'appareil, pas une donnée de l'activité). Un autre ordinateur, ou une restauration, ne
/// le reçoit donc jamais.
class StockageGoogleBureau {
  StockageGoogleBureau(this.fichier);

  final File fichier;

  /// Les réglages enregistrés ; des réglages vides si le fichier est absent ou illisible.
  Future<ReglagesGoogleBureau> lire() async {
    try {
      if (!await fichier.exists()) return const ReglagesGoogleBureau();
      return ReglagesGoogleBureau.depuisJson(jsonDecode(await fichier.readAsString()));
    } on FileSystemException {
      return const ReglagesGoogleBureau();
    } on FormatException {
      return const ReglagesGoogleBureau();
    }
  }

  /// Enregistre [reglages] (écrit à côté, puis renommé : un arrêt en cours d'écriture ne laisse pas un fichier tronqué).
  Future<void> ecrire(ReglagesGoogleBureau reglages) async {
    await fichier.parent.create(recursive: true);
    final File provisoire = File('${fichier.path}.tmp');
    await provisoire.writeAsString(jsonEncode(reglages.versJson()), flush: true);
    await provisoire.rename(fichier.path);
  }

  /// Oublie tout : l'accès saisi et l'autorisation.
  Future<void> effacer() async {
    try {
      if (await fichier.exists()) await fichier.delete();
    } on FileSystemException {
      // Rien de plus à faire : le fichier sera relu tel quel au prochain démarrage.
    }
  }
}
