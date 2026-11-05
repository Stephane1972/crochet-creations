#!/usr/bin/env python3
"""Fait signer l'APK de publication avec une clé stable, quand la CI la fournit.

`flutter create` (voir tool/setup_android.sh) génère un projet Android dont la version « release » est signée avec la
clé de débogage de la machine qui construit. Sur GitHub Actions, cette clé est recréée à chaque construction : deux APK
n'ont jamais la même signature, et Android refuse d'installer l'un par-dessus l'autre (il faut désinstaller, donc
perdre les données). La connexion à un compte Google (Drive) exige aussi une signature connue à l'avance.

Ce script modifie `android/app/build.gradle.kts` :
  - si la variable d'environnement ANDROID_KEYSTORE_FILE est définie, la version « release » est signée avec ce fichier
    (mot de passe : ANDROID_KEYSTORE_PASSWORD, alias : ANDROID_KEY_ALIAS) ;
  - sinon, rien ne change : la clé de débogage reste utilisée (essais en local, copies du dépôt sans les secrets).

Le script s'arrête avec une erreur claire si le fichier n'a pas la forme attendue : on préfère un échec visible à un
APK silencieusement signé avec la mauvaise clé. Il peut être relancé sans risque.
"""

from __future__ import annotations

import pathlib
import re
import sys

FICHIER = pathlib.Path("android/app/build.gradle.kts")
MARQUEUR = "ANDROID_KEYSTORE_FILE"

BLOC_SIGNATURE = """    // Clé de signature stable, fournie par la CI (voir tool/patch_signature_android.py). Sans elle : clé de débogage.
    val fichierCleSignature: String? = System.getenv("ANDROID_KEYSTORE_FILE")
    signingConfigs {
        if (fichierCleSignature != null) {
            create("publication") {
                storeFile = file(fichierCleSignature)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

"""

MOTIF_SIGNATURE_RELEASE = re.compile(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)')
NOUVELLE_SIGNATURE_RELEASE = (
    'signingConfig = signingConfigs.getByName(if (fichierCleSignature != null) "publication" else "debug")'
)


def echec(message: str, texte: str | None = None) -> None:
    print(f"ERREUR : {message}", file=sys.stderr)
    if texte is not None:
        print("--- contenu de " + str(FICHIER) + " ---", file=sys.stderr)
        print(texte, file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not FICHIER.exists():
        echec(f"{FICHIER} est introuvable (le dossier android/ a-t-il été créé par tool/setup_android.sh ?)")
    texte = FICHIER.read_text(encoding="utf-8")

    if MARQUEUR in texte:
        print("→ Signature : déjà préparée, rien à faire")
        return

    debut_types = re.search(r"^(\s*)buildTypes\s*\{", texte, flags=re.MULTILINE)
    if debut_types is None:
        echec("le bloc « buildTypes { » est introuvable", texte)
    if MOTIF_SIGNATURE_RELEASE.search(texte) is None:
        echec("la ligne « signingConfig = signingConfigs.getByName(\"debug\") » est introuvable", texte)

    # Le bloc des clés est inséré juste avant « buildTypes { » (dans « android { »), puis la version release
    # est branchée dessus.
    position = debut_types.start()
    texte = texte[:position] + BLOC_SIGNATURE + texte[position:]
    texte = MOTIF_SIGNATURE_RELEASE.sub(NOUVELLE_SIGNATURE_RELEASE, texte, count=1)

    FICHIER.write_text(texte, encoding="utf-8")
    print("→ Signature : la version release utilisera la clé stable si ANDROID_KEYSTORE_FILE est défini")


if __name__ == "__main__":
    main()
