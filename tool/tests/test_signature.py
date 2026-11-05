#!/usr/bin/env python3
"""Tests des scripts de signature de l'APK (tool/patch_signature_android.py et tool/empreinte_signature_apk.py).

Lancement (à la racine du dépôt) :
    python3 -m unittest discover -s tool/tests -v

Ils ne demandent ni Flutter ni SDK Android : le modèle Gradle de Flutter est une copie dans tool/tests/fixtures/ et l'APK
d'essai est fabriqué ici, avec un faux « bloc de signature » dont on connaît le certificat.
"""

from __future__ import annotations

import hashlib
import io
import os
import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

RACINE = pathlib.Path(__file__).resolve().parents[2]
OUTILS = RACINE / "tool"
MODELE_GRADLE = pathlib.Path(__file__).resolve().parent / "fixtures" / "build.gradle.kts.flutter-3.47.9"

FAUX_CERTIFICAT = b"certificat-de-test-" + bytes(range(64))


def champ(contenu: bytes) -> bytes:
    """Un champ « longueur sur 4 octets + contenu »."""
    return struct.pack("<I", len(contenu)) + contenu


def apk_avec_bloc_signature(identifiant: int = 0x7109871A, certificat: bytes = FAUX_CERTIFICAT) -> bytes:
    """Un zip minimal, avec un bloc de signature Android (v2 par défaut) inséré avant le répertoire central."""
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as archive:
        archive.writestr("AndroidManifest.xml", "<manifest/>")
    donnees = bytearray(tampon.getvalue())

    # Données signées : empreintes (vide), certificats (un seul), attributs (vide).
    donnees_signees = champ(b"") + champ(champ(certificat)) + champ(b"")
    signataire = champ(donnees_signees) + champ(b"") + champ(b"")  # + signatures + clé publique (ignorées)
    valeur = champ(champ(signataire))
    paire = struct.pack("<Q", 4 + len(valeur)) + struct.pack("<I", identifiant) + valeur
    taille = len(paire) + 8 + 16  # paires + 2e champ de taille + signature du bloc
    bloc = struct.pack("<Q", taille) + paire + struct.pack("<Q", taille) + b"APK Sig Block 42"

    fin = donnees.rfind(b"PK\x05\x06")
    (debut_repertoire,) = struct.unpack("<I", donnees[fin + 16 : fin + 20])
    donnees[fin + 16 : fin + 20] = struct.pack("<I", debut_repertoire + len(bloc))
    return bytes(donnees[:debut_repertoire]) + bloc + bytes(donnees[debut_repertoire:])


class EmpreinteSignatureApk(unittest.TestCase):
    def setUp(self) -> None:
        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)
        self.chemin = pathlib.Path(self.dossier.name)

    def ecrire_apk(self, nom: str = "essai.apk", **kwargs) -> pathlib.Path:
        apk = self.chemin / nom
        apk.write_bytes(apk_avec_bloc_signature(**kwargs))
        return apk

    def lancer(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", str(OUTILS / "empreinte_signature_apk.py"), *arguments],
            capture_output=True,
            text=True,
        )

    def test_lit_le_certificat_v2_et_v3(self) -> None:
        for identifiant in (0x7109871A, 0xF05368C0):
            apk = self.ecrire_apk(identifiant=identifiant)
            resultat = self.lancer(str(apk))
            self.assertEqual(resultat.returncode, 0, resultat.stdout + resultat.stderr)
            attendu = ":".join(f"{o:02X}" for o in hashlib.sha256(FAUX_CERTIFICAT).digest())
            self.assertIn(attendu, resultat.stdout)
            attendu_sha1 = ":".join(f"{o:02X}" for o in hashlib.sha1(FAUX_CERTIFICAT).digest())
            self.assertIn(attendu_sha1, resultat.stdout)

    def test_empreinte_attendue_conforme(self) -> None:
        apk = self.ecrire_apk()
        attendue = self.chemin / "attendue.txt"
        sha = ":".join(f"{o:02X}" for o in hashlib.sha256(FAUX_CERTIFICAT).digest())
        attendue.write_text(f"# commentaire\n\n{sha}\n", encoding="utf-8")
        resultat = self.lancer(str(apk), "--attendue", str(attendue))
        self.assertEqual(resultat.returncode, 0, resultat.stdout)
        self.assertIn("Conforme", resultat.stdout)

    def test_empreinte_attendue_differente_echoue(self) -> None:
        apk = self.ecrire_apk()
        attendue = self.chemin / "attendue.txt"
        attendue.write_text("00:11:22:33\n", encoding="utf-8")
        resultat = self.lancer(str(apk), "--attendue", str(attendue), "--github")
        self.assertEqual(resultat.returncode, 2, resultat.stdout)
        self.assertIn("::error", resultat.stdout)

    def test_ecrit_le_resume(self) -> None:
        apk = self.ecrire_apk()
        resume = self.chemin / "resume.txt"
        resultat = self.lancer(str(apk), "--ecrire", str(resume))
        self.assertEqual(resultat.returncode, 0)
        self.assertIn("SHA-256", resume.read_text(encoding="utf-8"))

    def test_fichier_illisible_donne_le_code_3(self) -> None:
        faux = self.chemin / "pas-un-apk.apk"
        faux.write_bytes(b"ceci n'est pas un zip")
        self.assertEqual(self.lancer(str(faux)).returncode, 3)
        self.assertEqual(self.lancer(str(self.chemin / "absent.apk")).returncode, 3)

    def test_zip_sans_bloc_de_signature_donne_le_code_3(self) -> None:
        tampon = io.BytesIO()
        with zipfile.ZipFile(tampon, "w") as archive:
            archive.writestr("a.txt", "a")
        apk = self.chemin / "non-signe.apk"
        apk.write_bytes(tampon.getvalue())
        self.assertEqual(self.lancer(str(apk)).returncode, 3)


class PatchSignatureAndroid(unittest.TestCase):
    def setUp(self) -> None:
        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)
        self.racine = pathlib.Path(self.dossier.name)
        (self.racine / "android" / "app").mkdir(parents=True)
        self.gradle = self.racine / "android" / "app" / "build.gradle.kts"

    def lancer(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", str(OUTILS / "patch_signature_android.py")],
            cwd=self.racine,
            capture_output=True,
            text=True,
        )

    def test_branche_la_cle_stable_sur_la_version_release(self) -> None:
        self.gradle.write_text(MODELE_GRADLE.read_text(encoding="utf-8"), encoding="utf-8")
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        texte = self.gradle.read_text(encoding="utf-8")
        self.assertIn('System.getenv("ANDROID_KEYSTORE_FILE")', texte)
        self.assertIn('System.getenv("ANDROID_KEYSTORE_PASSWORD")', texte)
        self.assertIn('System.getenv("ANDROID_KEY_ALIAS")', texte)
        self.assertIn('signingConfigs.getByName(if (fichierCleSignature != null) "publication" else "debug")', texte)
        # Le bloc des clés est déclaré avant « buildTypes », qui l'utilise.
        self.assertLess(texte.index("signingConfigs {"), texte.index("buildTypes {"))
        # Le reste du fichier est intact.
        self.assertIn("minSdk = flutter.minSdkVersion", texte)
        self.assertIn('source = "../.."', texte)

    def test_relance_sans_effet(self) -> None:
        self.gradle.write_text(MODELE_GRADLE.read_text(encoding="utf-8"), encoding="utf-8")
        self.assertEqual(self.lancer().returncode, 0)
        premier = self.gradle.read_text(encoding="utf-8")
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 0)
        self.assertEqual(self.gradle.read_text(encoding="utf-8"), premier)
        self.assertEqual(premier.count("signingConfigs {"), 1)

    def test_modele_inattendu_echoue_bruyamment(self) -> None:
        self.gradle.write_text("android {\n    namespace = \"x\"\n}\n", encoding="utf-8")
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 1)
        self.assertIn("ERREUR", resultat.stderr)

    def test_release_sans_ligne_de_signature_echoue(self) -> None:
        texte = MODELE_GRADLE.read_text(encoding="utf-8").replace(
            'signingConfig = signingConfigs.getByName("debug")', "// rien"
        )
        self.gradle.write_text(texte, encoding="utf-8")
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 1)
        self.assertEqual(self.gradle.read_text(encoding="utf-8"), texte)  # rien n'a été modifié

    def test_fichier_absent_echoue(self) -> None:
        self.assertEqual(self.lancer().returncode, 1)


if __name__ == "__main__":
    unittest.main()
