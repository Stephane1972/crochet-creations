#!/usr/bin/env python3
"""Génère les PNG d'icône Android à partir des logos SVG.

Usage (depuis la racine du dépôt) :
    pip install cairosvg pillow
    python3 tool/generate_icons.py

Fichiers produits dans assets/icon/ :
  - app_icon.png               icône classique (fond crème + logo)
  - app_icon_foreground.png    premier plan de l'icône adaptative (fond transparent)
  - app_icon_monochrome.png    version monochrome (icônes thématiques Android 13+)

Ils sont ensuite transformés en mipmaps par `dart run flutter_launcher_icons`
(voir tool/setup_android.sh).
"""
import io
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets" / "images" / "logo.svg"
LOGO_MONO = ROOT / "assets" / "images" / "logo_mono.svg"
OUT = ROOT / "assets" / "icon"
SIZE = 1024
CREAM = (251, 247, 244, 255)  # #FBF7F4


def render(svg: Path, size: int, background=None) -> Image.Image:
    png = cairosvg.svg2png(
        url=str(svg), output_width=size, output_height=size, background_color=background
    )
    return Image.open(io.BytesIO(png)).convert("RGBA")


def fit_centered(img: Image.Image, canvas: int, content: int) -> Image.Image:
    """Recadre sur le contenu visible, le met à l'échelle (côté max = `content`) et le centre."""
    bbox = img.getchannel("A").getbbox()
    cropped = img.crop(bbox)
    scale = content / max(cropped.size)
    cropped = cropped.resize(
        (round(cropped.width * scale), round(cropped.height * scale)), Image.LANCZOS
    )
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(
        cropped,
        ((canvas - cropped.width) // 2, (canvas - cropped.height) // 2),
        cropped,
    )
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    logo = render(LOGO, SIZE * 2)  # rendu x2 pour un recadrage net

    # 1) Icône classique : logo sur fond crème, ~76 % de la surface
    classic = Image.new("RGBA", (SIZE, SIZE), CREAM)
    classic.alpha_composite(fit_centered(logo, SIZE, round(SIZE * 0.76)))
    classic.convert("RGB").save(OUT / "app_icon.png")

    # 2) Premier plan adaptatif : zone de sécurité Android = cercle de 66/108 (≈ 61 %)
    fit_centered(logo, SIZE, round(SIZE * 0.56)).save(OUT / "app_icon_foreground.png")

    # 3) Monochrome : noir pur, l'opacité vient de la luminosité du logo mono sur fond blanc
    mono = render(LOGO_MONO, SIZE * 2, background="#FFFFFF").convert("L")
    alpha = mono.point(lambda v: 255 - v)
    mono_rgba = Image.new("RGBA", mono.size, (0, 0, 0, 0))
    mono_rgba.putalpha(alpha)
    fit_centered(mono_rgba, SIZE, round(SIZE * 0.56)).save(OUT / "app_icon_monochrome.png")

    print("Icônes générées dans", OUT)


if __name__ == "__main__":
    main()
