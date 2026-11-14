/// Configuration de la connexion à Google (Google Drive, étape 6 de l'évolution).
///
/// Il faut un projet Google Cloud gratuit (voir README, « Google Drive ») : un accès de type « Android » (nom du package et
/// empreinte SHA-1 de la clé de signature) et un accès de type « Application Web ». Seul l'**ID client de l'accès Web** est
/// connu de l'application : ce n'est pas un secret (il est visible dans toute application Android qui utilise Google).
///
/// Tant qu'il est vide, l'application s'ouvre normalement et l'écran « Google Drive » explique que la connexion n'est pas
/// encore configurée.

/// ID client Web fourni à la construction (`--dart-define=GOOGLE_WEB_CLIENT_ID=...`), s'il y en a un.
const String _clientWebDefini = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// ID client Web du projet Google Cloud de l'application, à renseigner une fois la configuration faite
/// (se termine par `.apps.googleusercontent.com`).
const String _clientWebParDefaut = '';

/// L'ID client Web utilisé : celui de la construction s'il existe, sinon celui du code.
String get clientWebGoogle => _clientWebDefini.isNotEmpty ? _clientWebDefini : _clientWebParDefaut;
