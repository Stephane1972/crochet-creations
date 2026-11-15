// L'« ID client » d'un accès Google Cloud (étape 6 de l'évolution) : ce que la personne colle dans l'application pour
// l'autoriser à se connecter à Google Drive. Ce n'est pas un secret.
//
// Un ID client est de la forme `<chiffres>-<lettres et chiffres>` suivi de `.apps.googleusercontent.com`.

/// Fin de tout ID client Google.
const String suffixeIdClientGoogle = '.apps.googleusercontent.com';

/// Début d'un « code secret » Google : il ne doit jamais être collé dans l'application.
const String debutCodeSecretGoogle = 'GOCSPX-';

final RegExp _blancs = RegExp(r'\s+');
final RegExp _signesAutour = RegExp(r'''^["'“”‘’«»,;]+|["'“”‘’«»,;]+$''');
final RegExp _formeIdClient = RegExp(r'^[0-9]{4,}-[A-Za-z0-9_-]{8,}$');

/// Nettoie ce qui a été collé : les espaces et les retours à la ligne (un texte copié depuis une page web ou un PDF en
/// contient souvent) et les guillemets ou virgules autour.
String nettoyerIdClientWeb(String saisie) => saisie.replaceAll(_blancs, '').replaceAll(_signesAutour, '');

/// Pourquoi [id] (déjà nettoyé par [nettoyerIdClientWeb]) n'est pas un ID client Google ; `null` s'il en a la forme.
String? erreurIdClientWeb(String id) {
  if (id.isEmpty) {
    return 'Collez l’ID client Web : il se termine par $suffixeIdClientGoogle.';
  }
  if (id.startsWith(debutCodeSecretGoogle)) {
    return 'Ceci est un « code secret » : ne le collez pas ici, et gardez-le pour vous. Il faut l’« ID client » '
        '(il se termine par $suffixeIdClientGoogle).';
  }
  if (!id.endsWith(suffixeIdClientGoogle)) {
    return 'Ce n’est pas un ID client Google : il doit se terminer par $suffixeIdClientGoogle.';
  }
  final String debut = id.substring(0, id.length - suffixeIdClientGoogle.length);
  if (!_formeIdClient.hasMatch(debut)) {
    return 'Cet ID n’a pas la forme attendue (des chiffres, un tiret, des lettres, puis $suffixeIdClientGoogle). '
        'Vérifiez qu’il est complet.';
  }
  return null;
}
