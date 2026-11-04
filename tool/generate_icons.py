#!/usr/bin/env python3
"""Prépare les images du logo de l'application à partir du logo fourni (carré).

Usage (depuis la racine du dépôt) :
    pip install pillow
    python3 tool/generate_icons.py

Entrée : assets/icon/logo_source.png (carré, 1254 x 1254 px aujourd'hui ; 1024 px au minimum).

Fichiers produits :
  - assets/icon/app_icon_foreground.png   premier plan de l'icône adaptative (fond transparent)
  - assets/images/logo_application.png    logo affiché dans l'application (écran de démarrage, accueil, réglages)

L'icône classique (Android avant la version 8) est logo_source.png lui-même ; le fond de l'icône adaptative est
la couleur du pourtour du logo (`adaptive_icon_background` dans pubspec.yaml). Ces PNG sont ensuite transformés
en icônes Android par `dart run flutter_launcher_icons` (voir tool/setup_android.sh).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icon" / "logo_source.png"
PREMIER_PLAN = ROOT / "assets" / "icon" / "app_icon_foreground.png"
LOGO_APPLICATION = ROOT / "assets" / "images" / "logo_application.png"

TAILLE_ICONE = 1024
# Zone de sécurité d'Android : l'icône adaptative est dessinée sur 108 dp, mais seul un disque d'environ 66 dp
# est toujours visible, quel que soit le masque (rond, carré arrondi…). Le logo entier est donc réduit pour que
# ses éléments restent visibles ; le fond est de la même couleur que son pourtour.
PART_PREMIER_PLAN = 0.62
# Couleur du pourtour du logo (médiane) : fond de l'icône adaptative, à garder égale à `adaptive_icon_background`.
FOND = "#FCE5E6"
# Le pourtour du logo n'est pas tout à fait uniforme (un peu plus foncé en bas) : ses bords sont estompés pour qu'ils
# se fondent dans le fond sans laisser de trait.
ESTOMPAGE = 0.04  # part de la largeur
TAILLE_LOGO_APPLICATION = 640


def main() -> None:
    logo = Image.open(SOURCE).convert("RGBA")

    cote = round(TAILLE_ICONE * PART_PREMIER_PLAN)
    reduit = logo.resize((cote, cote), Image.LANCZOS)
    marge = round(cote * ESTOMPAGE)
    masque = Image.new("L", (cote, cote), 0)
    ImageDraw.Draw(masque).rectangle((marge, marge, cote - marge, cote - marge), fill=255)
    reduit.putalpha(masque.filter(ImageFilter.GaussianBlur(marge / 2)))
    premier_plan = Image.new("RGBA", (TAILLE_ICONE, TAILLE_ICONE), (0, 0, 0, 0))
    decalage = (TAILLE_ICONE - cote) // 2
    premier_plan.alpha_composite(reduit, (decalage, decalage))
    premier_plan.save(PREMIER_PLAN, optimize=True)

    logo.resize((TAILLE_LOGO_APPLICATION, TAILLE_LOGO_APPLICATION), Image.LANCZOS).convert("RGB").save(
        LOGO_APPLICATION, optimize=True
    )

    print("Images générées :", PREMIER_PLAN.relative_to(ROOT), "et", LOGO_APPLICATION.relative_to(ROOT))


if __name__ == "__main__":
    main()
