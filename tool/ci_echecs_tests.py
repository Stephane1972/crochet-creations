#!/usr/bin/env python3
"""Publie chaque test en échec comme une « annotation » GitHub Actions distincte.

Une annotation est tronquée à environ 4 000 caractères : un seul bloc pour tous les échecs
en cachait la plupart. Ici, un test en échec = une annotation (10 au maximum), avec le message
d'erreur et le début de la pile d'appels.

Usage : python3 tool/ci_echecs_tests.py test-output.log
"""
import re
import sys

LIMITE_ANNOTATIONS = 10
LIMITE_CARACTERES = 3300
LIGNES_DE_PILE = 10

PROGRESSION = re.compile(r"^\d\d:\d\d \+\d+")
ECHEC = re.compile(r"^\d\d:\d\d \+\d+(?: [~-]\d+)*: (.*) \[E\]\s*$")


def encoder(texte: str) -> str:
    """Encodage attendu par GitHub pour un message d'annotation sur plusieurs lignes."""
    return texte.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def blocs_exception(lignes):
    """Blocs « EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK » : (nom du test, lignes du bloc)."""
    blocs = []
    i = 0
    while i < len(lignes):
        if "EXCEPTION CAUGHT" in lignes[i]:
            j = i + 1
            while j < len(lignes) and not re.fullmatch(r"═+", lignes[j].strip()):
                j += 1
            bloc = lignes[i : j + 1]
            nom = ""
            for k, ligne in enumerate(bloc):
                if ligne.startswith("The test description was:") and k + 1 < len(bloc):
                    nom = bloc[k + 1].strip()
            blocs.append((nom, bloc))
            i = j
        i += 1
    return blocs


def raccourcir(bloc):
    """Garde le message d'erreur et seulement les premières lignes de la pile d'appels."""
    for k, ligne in enumerate(bloc):
        if "this was the stack:" in ligne:
            return bloc[: k + 1 + LIGNES_DE_PILE]
    return bloc


def main() -> int:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        lignes = f.read().splitlines()

    blocs = blocs_exception(lignes)
    deja = set()
    envoyees = 0
    for i, ligne in enumerate(lignes):
        m = ECHEC.match(ligne)
        if not m:
            continue
        nom_complet = m.group(1)
        if nom_complet in deja:
            continue
        deja.add(nom_complet)

        detail = []
        for nom, bloc in blocs:
            if nom and nom_complet.endswith(nom):
                detail = raccourcir(bloc)
                break
        if not detail:
            # Échec d'un test ordinaire : le message suit la ligne [E].
            for suite in lignes[i + 1 :]:
                if PROGRESSION.match(suite):
                    break
                detail.append(suite)

        texte = "\n".join(detail).strip()[:LIMITE_CARACTERES] or "(pas de détail dans le journal)"
        titre = "Échec - " + nom_complet.split(": ", 1)[-1][:120]
        titre = titre.replace(",", " ").replace(":", " ")  # « , » et « : » séparent les propriétés
        print(f"::error title={encoder(titre)}::{encoder(texte)}")
        envoyees += 1
        if envoyees >= LIMITE_ANNOTATIONS:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
