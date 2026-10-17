# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la numérotation
[SemVer](https://semver.org/lang/fr/). Tant que la version 1.0.0 n'est pas publiée, chaque étape
validée augmente le numéro de version mineure (0.1.0, 0.2.0…).

## [Non publié]

## [0.1.0] — Étape 1 : fondations (en attente de validation)

### Ajouté
- Projet Flutter (Dart, Material 3, Riverpod) organisé en couches `presentation` / `domain` / `data`.
- Thèmes jour et nuit aux couleurs de la charte (rose pastel, rose soutenu, vert sauge), avec contrastes
  de texte vérifiés par des tests ; mode automatique, jour ou nuit au choix dans *Plus → Réglages*.
- Titres en Poppins (police embarquée), texte courant en police système ; boutons arrondis, cartes à ombre légère.
- Logo SVG (pelote de laine rose et crochet vert), version monochrome pour les factures,
  icône Android (classique, adaptative et monochrome).
- Écran de démarrage avec le logo.
- Navigation à 5 onglets (Accueil, Produits, Vente, Clients, Plus) ; le bouton « retour » ramène à l'accueil.
- Écran d'accueil : en-tête (salutation et date), raccourcis, emplacements des chiffres clés,
  suivi des seuils de franchise de TVA (85 000 € / 37 500 €).
- Écrans « Bientôt disponible » pour les écrans des étapes suivantes.
- Interface entièrement en français.
- Utilitaires `formatEuros` (montants en centimes) et dates en français.
- Documentation : README, ARCHITECTURE, ROADMAP, CHANGELOG.
- Tests unitaires (montants, dates, thèmes, contrastes) et tests de widgets (splash, navigation, thème).
- Construction automatique de l'APK avec GitHub Actions, scripts `tool/setup_android.sh` et `tool/generate_icons.py`.

### Limites connues
- Aucun chiffre n'est calculé : pas encore de base de données (étape 2).
- Le choix jour/nuit n'est pas mémorisé entre deux lancements (étape 2).
- Le code n'a pas pu être compilé ni testé dans l'environnement de rédaction (SDK Flutter inaccessible) :
  la première exécution de GitHub Actions fait foi.
