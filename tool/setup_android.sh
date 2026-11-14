#!/usr/bin/env bash
# Prépare la plateforme Android de l'application :
#   1. crée le dossier android/ s'il n'existe pas (via `flutter create`) ;
#   2. règle le nom affiché sous l'icône : « Un p’tit crochet dans les stocks » ;
#   3. prépare la signature de l'APK : clé stable si la CI la fournit, sinon clé de débogage (tool/patch_signature_android.py) ;
#   4. génère les icônes de l'application à partir de assets/icon/ (logo fourni, voir tool/generate_icons.py).
#
# Utilisation (à la racine du dépôt, après `flutter pub get`) :
#   bash tool/setup_android.sh
#
# Le script peut être relancé sans risque. Il est aussi utilisé par la CI GitHub Actions.
set -euo pipefail

cd "$(dirname "$0")/.."

ORG="fr.crochetcreations"   # identifiant de l'application : fr.crochetcreations.crochet_creations
PROJET="crochet_creations"
MANIFEST="android/app/src/main/AndroidManifest.xml"
# Nom affiché sous l'icône : à garder identique à AppConstants.nomApplication (lib/core/constants/app_constants.dart).
# L'apostrophe est typographique (’) : pas besoin de la protéger dans le XML.
NOM_AFFICHE="Un p’tit crochet dans les stocks"

if [ ! -d android ]; then
  echo "→ Création du dossier android/"

  # Par précaution, on met de côté nos fichiers : `flutter create` ne doit rien écraser.
  SAUVEGARDE="$(mktemp -d)"
  FICHIERS="pubspec.yaml README.md analysis_options.yaml .gitignore lib/main.dart test/widget_test.dart"
  for f in $FICHIERS; do
    if [ -f "$f" ]; then
      mkdir -p "$SAUVEGARDE/$(dirname "$f")"
      cp "$f" "$SAUVEGARDE/$f"
    fi
  done

  flutter create --platforms=android --org "$ORG" --project-name "$PROJET" .

  for f in $FICHIERS; do
    if [ -f "$SAUVEGARDE/$f" ]; then
      cp "$SAUVEGARDE/$f" "$f"
    fi
  done
  rm -rf "$SAUVEGARDE"

  flutter pub get
else
  echo "→ Le dossier android/ existe déjà : création ignorée"
fi

echo "→ Nom affiché sous l'icône : $NOM_AFFICHE"
sed -i "s|android:label=\"[^\"]*\"|android:label=\"$NOM_AFFICHE\"|" "$MANIFEST"

echo "→ Permission Internet (Google Drive)"
# `flutter create` ne déclare Internet que pour le débogage : sans cette ligne, une application installée depuis l'APK
# ne pourrait joindre ni Google ni Drive. Elle ne sert qu'à l'envoi vers Drive, demandé par la personne.
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i '0,/<manifest[^>]*>/s||&\n    <uses-permission android:name="android.permission.INTERNET"/>|' "$MANIFEST"
fi
grep -q 'android.permission.INTERNET' "$MANIFEST" || { echo "✗ Permission Internet non ajoutée au manifeste" >&2; exit 1; }

echo "→ Signature de l'APK"
python3 tool/patch_signature_android.py

echo "→ Génération des icônes"
dart run flutter_launcher_icons

echo "✓ Android est prêt. Vous pouvez lancer : flutter run   ou   flutter build apk --release"
