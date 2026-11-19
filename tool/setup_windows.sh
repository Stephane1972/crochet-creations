#!/usr/bin/env bash
# Prépare la plateforme Windows de l'application (même principe que tool/setup_android.sh) :
#   1. crée le dossier windows/ s'il n'existe pas (via `flutter create`) ;
#   2. règle le titre de la fenêtre, sa taille de départ et les noms du fichier .exe (ils servent aussi à ranger les
#      données : dossier « données d'application » de l'utilisateur) ;
#   3. génère l'icône de l'application à partir du logo fourni.
#
# Utilisation (à la racine du dépôt, après `flutter pub get`) :
#   bash tool/setup_windows.sh
#
# Le script peut être relancé sans risque. Il est utilisé par la CI GitHub Actions (workflow « Windows »). Il ne touche
# à rien de ce qui concerne Android.
set -euo pipefail

cd "$(dirname "$0")/.."

ORG="fr.crochetcreations"   # même identifiant que sous Android
PROJET="crochet_creations"
# Nom affiché dans la barre de titre et dans les propriétés du .exe : à garder proche de AppConstants.nomApplication.
# Apostrophe droite (') : le fichier C++ n'a pas à être en UTF-8.
NOM_FENETRE="Un p'tit crochet dans les stocks"
PRINCIPAL="windows/runner/main.cpp"
RESSOURCES="windows/runner/Runner.rc"

if [ ! -d windows ]; then
  echo "→ Création du dossier windows/"

  # Par précaution, on met de côté nos fichiers : `flutter create` ne doit rien écraser.
  SAUVEGARDE="$(mktemp -d)"
  FICHIERS="pubspec.yaml README.md analysis_options.yaml .gitignore lib/main.dart test/widget_test.dart"
  for f in $FICHIERS; do
    if [ -f "$f" ]; then
      mkdir -p "$SAUVEGARDE/$(dirname "$f")"
      cp "$f" "$SAUVEGARDE/$f"
    fi
  done

  flutter create --platforms=windows --org "$ORG" --project-name "$PROJET" .

  for f in $FICHIERS; do
    if [ -f "$SAUVEGARDE/$f" ]; then
      cp "$SAUVEGARDE/$f" "$f"
    fi
  done
  rm -rf "$SAUVEGARDE"

  flutter pub get
else
  echo "→ Le dossier windows/ existe déjà : création ignorée"
fi

echo "→ Titre de la fenêtre : $NOM_FENETRE"
sed -i "s|L\"$PROJET\"|L\"$NOM_FENETRE\"|" "$PRINCIPAL"
grep -q "L\"$NOM_FENETRE\"" "$PRINCIPAL" || { echo "✗ Titre de fenêtre non réglé dans $PRINCIPAL" >&2; exit 1; }

echo "→ Taille de départ de la fenêtre : 720 × 960 (celle d'un grand téléphone, redimensionnable)"
sed -i 's|Win32Window::Size size([0-9]*, *[0-9]*);|Win32Window::Size size(720, 960);|' "$PRINCIPAL"
grep -q "size(720, 960)" "$PRINCIPAL" || { echo "✗ Taille de fenêtre non réglée dans $PRINCIPAL" >&2; exit 1; }

echo "→ Noms du produit (propriétés du .exe et dossier des données)"
sed -i "s|\(VALUE \"FileDescription\", \)\"[^\"]*\"|\1\"$NOM_FENETRE\"|; s|\(VALUE \"ProductName\", \)\"[^\"]*\"|\1\"$NOM_FENETRE\"|" "$RESSOURCES"
grep -q "VALUE \"ProductName\", \"$NOM_FENETRE\"" "$RESSOURCES" || { echo "✗ Nom du produit non réglé dans $RESSOURCES" >&2; exit 1; }

echo "→ Icône de l'application"
dart run flutter_launcher_icons -f tool/flutter_launcher_icons_windows.yaml
test -f windows/runner/resources/app_icon.ico || { echo "✗ Icône non générée" >&2; exit 1; }

echo "✓ Windows est prêt. Vous pouvez lancer : flutter build windows --release"
