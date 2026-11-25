#!/usr/bin/env python3
"""Tests du script qui prépare le projet Android aux notifications (tool/patch_notifications_android.py).

Lancement (à la racine du dépôt) :
    python3 -m unittest discover -s tool/tests -v

Ils ne demandent ni Flutter ni SDK Android : le modèle Gradle de Flutter est une copie dans tool/tests/fixtures/ et le manifeste
d'essai reprend la forme de celui que crée `flutter create`.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

RACINE = pathlib.Path(__file__).resolve().parents[2]
OUTILS = RACINE / "tool"
MODELE_GRADLE = pathlib.Path(__file__).resolve().parent / "fixtures" / "build.gradle.kts.flutter-3.47.9"

MANIFESTE = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="Un p’tit crochet dans les stocks"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
"""

ESPACE_ANDROID = "{http://schemas.android.com/apk/res/android}"


class PatchNotificationsAndroid(unittest.TestCase):
    def setUp(self) -> None:
        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)
        self.racine = pathlib.Path(self.dossier.name)
        (self.racine / "android" / "app" / "src" / "main").mkdir(parents=True)
        self.gradle = self.racine / "android" / "app" / "build.gradle.kts"
        self.manifeste = self.racine / "android" / "app" / "src" / "main" / "AndroidManifest.xml"

    def preparer(self, gradle: str | None = None, manifeste: str | None = MANIFESTE) -> None:
        self.gradle.write_text(MODELE_GRADLE.read_text(encoding="utf-8") if gradle is None else gradle, encoding="utf-8")
        if manifeste is not None:
            self.manifeste.write_text(manifeste, encoding="utf-8")

    def lancer(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", str(OUTILS / "patch_notifications_android.py")],
            cwd=self.racine,
            capture_output=True,
            text=True,
        )

    def lire_gradle(self) -> str:
        return self.gradle.read_text(encoding="utf-8")

    def lire_manifeste(self) -> str:
        return self.manifeste.read_text(encoding="utf-8")

    # --- Manifeste ---------------------------------------------------------------------------------------------

    def test_manifeste_permission_et_recepteurs(self) -> None:
        self.preparer()
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 0, resultat.stderr)

        racine = ET.fromstring(self.lire_manifeste())  # toujours du XML valide
        permissions = [p.get(ESPACE_ANDROID + "name") for p in racine.findall("uses-permission")]
        self.assertIn("android.permission.RECEIVE_BOOT_COMPLETED", permissions)
        self.assertIn("android.permission.INTERNET", permissions)  # l'existant est gardé

        application = racine.find("application")
        self.assertIsNotNone(application)
        recepteurs = {r.get(ESPACE_ANDROID + "name"): r for r in application.findall("receiver")}
        self.assertEqual(
            set(recepteurs),
            {
                "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver",
                "com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver",
            },
        )
        for recepteur in recepteurs.values():
            self.assertEqual(recepteur.get(ESPACE_ANDROID + "exported"), "false")
        actions = {
            a.get(ESPACE_ANDROID + "name")
            for a in recepteurs["com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"].iter("action")
        }
        self.assertIn("android.intent.action.BOOT_COMPLETED", actions)
        self.assertIn("android.intent.action.MY_PACKAGE_REPLACED", actions)

    def test_manifeste_le_reste_est_intact(self) -> None:
        self.preparer()
        self.assertEqual(self.lancer().returncode, 0)
        texte = self.lire_manifeste()
        self.assertIn('android:label="Un p’tit crochet dans les stocks"', texte)
        self.assertIn('android:name=".MainActivity"', texte)
        self.assertIn('android:name="flutterEmbedding"', texte)
        self.assertIn("<queries>", texte)
        # Les récepteurs sont dans « application », avant sa balise fermante ; la permission est avant « application ».
        self.assertLess(texte.index("ScheduledNotificationReceiver"), texte.index("</application>"))
        self.assertLess(texte.index("RECEIVE_BOOT_COMPLETED"), texte.index("<application"))
        self.assertLess(texte.index("</application>"), texte.index("<queries>"))

    # --- Gradle ------------------------------------------------------------------------------------------------

    def test_gradle_desugaring_multidex_et_compile_sdk(self) -> None:
        self.preparer()
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        texte = self.lire_gradle()

        self.assertIn("isCoreLibraryDesugaringEnabled = true", texte)
        self.assertIn("multiDexEnabled = true", texte)
        self.assertIn('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', texte)
        self.assertIn("compileSdk = maxOf(flutter.compileSdkVersion, 37)", texte)
        # Chaque réglage est dans son bloc.
        self.assertLess(texte.index("compileOptions {"), texte.index("isCoreLibraryDesugaringEnabled"))
        self.assertLess(texte.index("isCoreLibraryDesugaringEnabled"), texte.index("sourceCompatibility"))
        self.assertLess(texte.index("defaultConfig {"), texte.index("multiDexEnabled"))
        self.assertLess(texte.index("multiDexEnabled"), texte.index("minSdk"))
        self.assertGreater(texte.index("coreLibraryDesugaring("), texte.index("flutter {"))
        # Le reste du fichier est intact.
        self.assertIn("minSdk = flutter.minSdkVersion", texte)
        self.assertIn('source = "../.."', texte)
        self.assertIn("jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17", texte)

    def test_gradle_dependances_existantes_completees(self) -> None:
        modele = MODELE_GRADLE.read_text(encoding="utf-8") + '\ndependencies {\n    implementation("androidx.core:core:1.0.0")\n}\n'
        self.preparer(gradle=modele)
        self.assertEqual(self.lancer().returncode, 0)
        texte = self.lire_gradle()
        self.assertEqual(texte.count("dependencies {"), 1)
        self.assertIn('implementation("androidx.core:core:1.0.0")', texte)
        self.assertIn("coreLibraryDesugaring(", texte)

    def test_gradle_compile_sdk_ecrit_en_dur_est_releve_sans_jamais_baisser(self) -> None:
        for ancien, attendu in (("34", "37"), ("37", "37"), ("40", "40")):
            with self.subTest(ancien=ancien):
                modele = MODELE_GRADLE.read_text(encoding="utf-8").replace(
                    "compileSdk = flutter.compileSdkVersion", f"compileSdk = {ancien}"
                )
                self.preparer(gradle=modele)
                self.assertEqual(self.lancer().returncode, 0)
                self.assertIn(f"compileSdk = {attendu}", self.lire_gradle())

    # --- Relance, erreurs --------------------------------------------------------------------------------------

    def test_relance_sans_effet(self) -> None:
        self.preparer()
        self.assertEqual(self.lancer().returncode, 0)
        gradle, manifeste = self.lire_gradle(), self.lire_manifeste()

        resultat = self.lancer()

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertEqual(self.lire_gradle(), gradle)
        self.assertEqual(self.lire_manifeste(), manifeste)
        self.assertEqual(gradle.count("isCoreLibraryDesugaringEnabled"), 1)
        self.assertEqual(gradle.count("multiDexEnabled"), 1)
        self.assertEqual(gradle.count("coreLibraryDesugaring("), 1)
        self.assertEqual(manifeste.count("RECEIVE_BOOT_COMPLETED"), 1)
        self.assertEqual(manifeste.count("android:name=\"com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver\""), 1)

    def test_gradle_inattendu_echoue_bruyamment(self) -> None:
        self.preparer(gradle='android {\n    namespace = "x"\n}\n')
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 1)
        self.assertIn("ERREUR", resultat.stderr)

    def test_manifeste_inattendu_echoue_bruyamment(self) -> None:
        self.preparer(manifeste="<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n</manifest>\n")
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 1)
        self.assertIn("ERREUR", resultat.stderr)
        self.assertIn("</application>", resultat.stderr)

    def test_fichiers_absents_echouent(self) -> None:
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 1)
        self.assertIn("introuvable", resultat.stderr)


if __name__ == "__main__":
    unittest.main()
