#!/usr/bin/env bash
# Prépare la plateforme Android de l'application :
#   1. crée le dossier android/ s'il n'existe pas (via `flutter create`) ;
#   2. règle le nom affiché sous l'icône : « Crochet & Créations » ;
#   3. génère les icônes de l'application à partir de assets/icon/.
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

echo "→ Nom affiché sous l'icône : Crochet & Créations"
# « \&amp; » : le « & » doit être écrit « &amp; » en XML, et protégé pour sed.
sed -i 's|android:label="[^"]*"|android:label="Crochet \&amp; Créations"|' "$MANIFEST"

echo "→ Génération des icônes"
dart run flutter_launcher_icons

echo "✓ Android est prêt. Vous pouvez lancer : flutter run   ou   flutter build apk --release"
