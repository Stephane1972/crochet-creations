#!/usr/bin/env python3
"""Prépare le projet Android aux notifications programmées (rappel de la déclaration des recettes).

La bibliothèque flutter_local_notifications demande trois choses au projet Android généré par `flutter create`
(voir tool/setup_android.sh) :
  1. dans android/app/build.gradle.kts : le « desugaring » des bibliothèques Java (`isCoreLibraryDesugaringEnabled`,
     la dépendance `coreLibraryDesugaring`) et `multiDexEnabled` ; la version de compilation (`compileSdk`) doit aussi
     être au moins 37 ;
  2. dans AndroidManifest.xml : la permission RECEIVE_BOOT_COMPLETED (rétablir les rappels après un redémarrage du
     téléphone) ;
  3. dans AndroidManifest.xml : les deux récepteurs ScheduledNotificationReceiver (affiche la notification à l'heure
     prévue) et ScheduledNotificationBootReceiver (la reprogramme après un redémarrage).
La permission POST_NOTIFICATIONS (Android 13 et plus) vient de la bibliothèque elle-même.

Sans ces réglages, la notification n'apparaîtrait jamais, sans aucune erreur visible : le script s'arrête donc avec un
message clair si un fichier n'a pas la forme attendue. Il peut être relancé sans risque (rien n'est ajouté deux fois).
"""

from __future__ import annotations

import pathlib
import re
import sys

MANIFESTE = pathlib.Path("android/app/src/main/AndroidManifest.xml")
GRADLE = pathlib.Path("android/app/build.gradle.kts")

COMPILE_SDK_MINIMUM = 37
DESUCRAGE = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'

PERMISSION_DEMARRAGE = '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'

RECEPTEURS = """        <!-- Notifications programmées (rappel de la déclaration des recettes) : voir tool/patch_notifications_android.py -->
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""


def echec(message: str, fichier: pathlib.Path, texte: str) -> None:
    print(f"ERREUR : {message}", file=sys.stderr)
    print(f"--- contenu de {fichier} ---", file=sys.stderr)
    print(texte, file=sys.stderr)
    sys.exit(1)


def lire(fichier: pathlib.Path) -> str:
    if not fichier.exists():
        print(f"ERREUR : {fichier} est introuvable (le dossier android/ a-t-il été créé par tool/setup_android.sh ?)", file=sys.stderr)
        sys.exit(1)
    return fichier.read_text(encoding="utf-8")


def preparer_manifeste() -> None:
    texte = lire(MANIFESTE)

    if "android.permission.RECEIVE_BOOT_COMPLETED" not in texte:
        ouverture = re.search(r"<manifest[^>]*>\n", texte)
        if ouverture is None:
            echec("la balise « <manifest ...> » est introuvable", MANIFESTE, texte)
        texte = texte[: ouverture.end()] + PERMISSION_DEMARRAGE + texte[ouverture.end() :]

    if "ScheduledNotificationReceiver" not in texte:
        fermeture = texte.rfind("</application>")
        if fermeture < 0:
            echec("la balise « </application> » est introuvable", MANIFESTE, texte)
        texte = texte[:fermeture].rstrip(" ") + RECEPTEURS + "    " + texte[fermeture:]

    MANIFESTE.write_text(texte, encoding="utf-8")
    print("→ Manifeste : permission de démarrage et récepteurs des notifications programmées")


def inserer_apres(texte: str, motif: str, ligne: str, fichier: pathlib.Path, description: str) -> str:
    """Insère [ligne] (avec son retour à la ligne) juste après la première ligne qui correspond à [motif]."""
    trouve = re.search(motif, texte, flags=re.MULTILINE)
    if trouve is None:
        echec(f"{description} est introuvable", fichier, texte)
    fin_de_ligne = texte.index("\n", trouve.end()) + 1
    return texte[:fin_de_ligne] + ligne + texte[fin_de_ligne:]


def preparer_gradle() -> None:
    texte = lire(GRADLE)

    # 1. Desugaring dans « compileOptions { ... } ».
    if "isCoreLibraryDesugaringEnabled" not in texte:
        texte = inserer_apres(
            texte,
            r"^\s*compileOptions\s*\{",
            "        isCoreLibraryDesugaringEnabled = true\n",
            GRADLE,
            "le bloc « compileOptions { »",
        )

    # 2. multiDex dans « defaultConfig { ... } ».
    if "multiDexEnabled" not in texte:
        texte = inserer_apres(
            texte,
            r"^\s*defaultConfig\s*\{",
            "        multiDexEnabled = true\n",
            GRADLE,
            "le bloc « defaultConfig { »",
        )

    # 3. La dépendance de desugaring, dans le bloc « dependencies { » (créé à la fin du fichier s'il n'existe pas).
    if "coreLibraryDesugaring(" not in texte:
        if re.search(r"^dependencies\s*\{", texte, flags=re.MULTILINE):
            texte = inserer_apres(texte, r"^dependencies\s*\{", f"    {DESUCRAGE}\n", GRADLE, "le bloc « dependencies { »")
        else:
            texte = texte.rstrip("\n") + f"\n\ndependencies {{\n    {DESUCRAGE}\n}}\n"

    # 4. Version de compilation : au moins 37 (celle que demande la bibliothèque), sans jamais la baisser.
    ancienne = "compileSdk = flutter.compileSdkVersion"
    nouvelle = f"compileSdk = maxOf(flutter.compileSdkVersion, {COMPILE_SDK_MINIMUM})"
    if nouvelle not in texte:
        if ancienne in texte:
            texte = texte.replace(ancienne, nouvelle, 1)
        elif re.search(r"compileSdk\s*=\s*\d+", texte):
            # Un nombre écrit en dur : on le relève s'il est trop bas.
            def relever(m: re.Match[str]) -> str:
                return f"compileSdk = {max(int(m.group(1)), COMPILE_SDK_MINIMUM)}"

            texte = re.sub(r"compileSdk\s*=\s*(\d+)", relever, texte, count=1)
        else:
            echec("la ligne « compileSdk = ... » est introuvable", GRADLE, texte)

    GRADLE.write_text(texte, encoding="utf-8")
    print("→ Gradle : desugaring, multiDex et compileSdk >= 37 pour les notifications")


def main() -> None:
    preparer_manifeste()
    preparer_gradle()


if __name__ == "__main__":
    main()
