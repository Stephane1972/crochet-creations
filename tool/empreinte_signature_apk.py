#!/usr/bin/env python3
"""Affiche l'empreinte du certificat qui a signé un APK, et la compare à l'empreinte attendue.

Utilisation :
    python3 tool/empreinte_signature_apk.py APK [--attendue FICHIER] [--ecrire FICHIER] [--github]

  - APK       : le fichier .apk à examiner (par exemple build/app/outputs/flutter-apk/app-release.apk) ;
  - --attendue: fichier texte contenant l'empreinte SHA-256 attendue (par exemple tool/signature_attendue.txt) ;
  - --ecrire  : écrit un petit résumé lisible (mode de signature, SHA-256, SHA-1) dans ce fichier ;
  - --github  : écrit aussi le résumé dans le « résumé d'étape » de GitHub Actions et publie les avertissements/erreurs
                sous forme d'annotations.

Le script lit lui-même le « bloc de signature » de l'APK (schémas v3 puis v2 d'Android) : il n'a besoin ni du SDK Android
ni d'`apksigner`. L'empreinte est celle du certificat, comme l'affichent `keytool -list -v` et `apksigner --print-certs` ;
le SHA-1 est celui que demande la console Google Cloud pour créer l'accès « application Android » (connexion à Google Drive).

Codes de sortie : 0 = lu (et conforme si --attendue), 2 = empreinte différente de l'attendue, 3 = APK illisible.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys

IDENTIFIANT_BLOC_V2 = 0x7109871A
IDENTIFIANT_BLOC_V3 = 0xF05368C0
SIGNATURE_BLOC = b"APK Sig Block 42"


class ApkIllisible(Exception):
    pass


def _lire_bloc(donnees: bytes, debut: int) -> tuple[bytes, int]:
    """Lit un champ « longueur sur 4 octets + contenu » ; renvoie (contenu, position suivante)."""
    if debut + 4 > len(donnees):
        raise ApkIllisible("bloc de signature tronqué")
    (longueur,) = struct.unpack("<I", donnees[debut : debut + 4])
    fin = debut + 4 + longueur
    if fin > len(donnees):
        raise ApkIllisible("bloc de signature tronqué")
    return donnees[debut + 4 : fin], fin


def certificat_signataire(chemin: str) -> bytes:
    """Renvoie le certificat (DER) du premier signataire de l'APK."""
    with open(chemin, "rb") as f:
        donnees = f.read()

    # Fin du « répertoire central » du zip : c'est juste avant que se trouve le bloc de signature.
    fin_zip = donnees.rfind(b"PK\x05\x06")
    if fin_zip < 0 or fin_zip + 20 > len(donnees):
        raise ApkIllisible("ce n'est pas un fichier zip/APK")
    (debut_repertoire,) = struct.unpack("<I", donnees[fin_zip + 16 : fin_zip + 20])
    if debut_repertoire < 32 or donnees[debut_repertoire - 16 : debut_repertoire] != SIGNATURE_BLOC:
        raise ApkIllisible("aucun bloc de signature v2/v3 (APK non signé, ou signé seulement à l'ancienne mode v1)")

    (taille_bloc,) = struct.unpack("<Q", donnees[debut_repertoire - 24 : debut_repertoire - 16])
    debut_bloc = debut_repertoire - taille_bloc - 8
    if debut_bloc < 0:
        raise ApkIllisible("bloc de signature incohérent")

    # Le bloc contient des paires « identifiant → valeur ».
    paires: dict[int, bytes] = {}
    position = debut_bloc + 8
    limite = debut_repertoire - 24
    while position < limite:
        (longueur,) = struct.unpack("<Q", donnees[position : position + 8])
        (identifiant,) = struct.unpack("<I", donnees[position + 8 : position + 12])
        paires[identifiant] = donnees[position + 12 : position + 8 + longueur]
        position += 8 + longueur

    for identifiant in (IDENTIFIANT_BLOC_V3, IDENTIFIANT_BLOC_V2):
        valeur = paires.get(identifiant)
        if valeur is None:
            continue
        # signataires → premier signataire → données signées → (empreintes, certificats) → premier certificat
        signataires, _ = _lire_bloc(valeur, 0)
        signataire, _ = _lire_bloc(signataires, 0)
        donnees_signees, _ = _lire_bloc(signataire, 0)
        _, apres_empreintes = _lire_bloc(donnees_signees, 0)
        certificats, _ = _lire_bloc(donnees_signees, apres_empreintes)
        certificat, _ = _lire_bloc(certificats, 0)
        return certificat

    raise ApkIllisible("le bloc de signature ne contient ni signature v2 ni signature v3")


def formater(empreinte: bytes) -> str:
    """AB:CD:… en majuscules, comme keytool."""
    return ":".join(f"{octet:02X}" for octet in empreinte)


def normaliser(texte: str) -> str:
    return "".join(c for c in texte.lower() if c in "0123456789abcdef")


def lire_attendue(chemin: str) -> str:
    """Première ligne non vide, non commentée (#) du fichier."""
    with open(chemin, encoding="utf-8") as f:
        for ligne in f:
            ligne = ligne.strip()
            if ligne and not ligne.startswith("#"):
                return normaliser(ligne)
    return ""


def annoter(niveau: str, titre: str, message: str, github: bool) -> None:
    if github:
        print(f"::{niveau} title={titre}::{message}")
    else:
        print(f"{niveau.upper()} — {titre} : {message}")


def main() -> int:
    analyseur = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    analyseur.add_argument("apk")
    analyseur.add_argument("--attendue")
    analyseur.add_argument("--ecrire")
    analyseur.add_argument("--github", action="store_true")
    arguments = analyseur.parse_args()

    try:
        certificat = certificat_signataire(arguments.apk)
    except (ApkIllisible, OSError, struct.error) as erreur:
        annoter("warning", "Signature de l'APK illisible", str(erreur), arguments.github)
        return 3

    sha256 = hashlib.sha256(certificat).digest()
    sha1 = hashlib.sha1(certificat).digest()
    attendue = lire_attendue(arguments.attendue) if arguments.attendue else None

    if attendue is None:
        verdict = "Empreinte lue (aucune empreinte attendue à comparer)."
    elif attendue == sha256.hex():
        verdict = "Conforme à l'empreinte attendue : la signature est la clé stable."
    else:
        verdict = (
            "DIFFÉRENTE de l'empreinte attendue : cet APK n'est pas signé avec la clé stable "
            "(secrets GitHub absents, ou autre clé). Il ne s'installera pas par-dessus la version précédente."
        )

    lignes = [
        verdict,
        f"Certificat SHA-256 : {formater(sha256)}",
        f"Certificat SHA-1   : {formater(sha1)}",
    ]
    print("\n".join(lignes))

    if arguments.ecrire:
        with open(arguments.ecrire, "w", encoding="utf-8") as f:
            f.write("\n".join(lignes) + "\n")

    if arguments.github:
        resume = os.environ.get("GITHUB_STEP_SUMMARY")
        if resume:
            with open(resume, "a", encoding="utf-8") as f:
                f.write("### Signature de l'APK\n\n" + "\n".join(f"- {ligne}" for ligne in lignes) + "\n")

    if attendue is not None and attendue != sha256.hex():
        annoter("error", "Signature de l'APK différente de l'attendue", verdict, arguments.github)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
