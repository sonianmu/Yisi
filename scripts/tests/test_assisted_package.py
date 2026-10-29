import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "macOS signing tools required")
class AssistedPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="yisi-package-test-")
        self.directory = Path(self.temporary.name)
        self.app = self.directory / "Yisi.app"
        binary = self.app / "Contents/MacOS/Yisi"
        binary.parent.mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", binary)
        binary.chmod(0o755)
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.sonianmu.yisi", "CFBundleExecutable": "Yisi",
                          "CFBundlePackageType": "APPL", "CFBundleVersion": "0.0.0"}, stream)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(self.app)], check=True, capture_output=True)
        self.script = self.directory / "Install Yisi.command"
        shutil.copy2(ROOT / "scripts/install-assisted.command", self.script)
        self.manifest = self.directory / "SHA256.txt"
        self.manifest.write_text(hashlib.sha256(binary.read_bytes()).hexdigest() + "  Yisi.app/Contents/MacOS/Yisi\n")

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self, *arguments, input=""):
        return subprocess.run(["/bin/bash", str(self.script), *arguments], input=input,
                              text=True, capture_output=True, timeout=20)

    def test_dry_run_validates_signed_payload_without_installing(self):
        result = self.invoke("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Dry run: no files or security settings changed.", result.stdout)
        self.assertIn("Gatekeeper, SIP and privacy permissions stay unchanged.", result.stdout)
        self.assertFalse(any(self.directory.glob(".Yisi-*")))

    def test_default_confirmation_cancels(self):
        result = self.invoke(input="\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Cancelled", result.stdout)
        self.assertFalse(any(self.directory.glob(".Yisi-*")))

    def test_missing_or_tampered_manifest_rejects_before_confirmation(self):
        self.manifest.write_text("0" * 64 + "  Yisi.app/Contents/MacOS/Yisi\n")
        result = self.invoke("--dry-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Payload checksum mismatch", result.stderr)
        self.manifest.unlink()
        self.assertNotEqual(self.invoke("--dry-run").returncode, 0)

    def test_symbolic_link_payload_is_rejected(self):
        moved = self.directory / "Other.app"
        self.app.rename(moved)
        self.app.symlink_to(moved)
        self.assertNotEqual(self.invoke("--dry-run").returncode, 0)

    def test_no_global_security_commands_or_privacy_resets(self):
        script = self.script.read_text()
        for forbidden in ["sudo ", "spctl ", "csrutil ", "tccutil ", "TCC.db", "xattr -cr", "codesign --force"]:
            self.assertNotIn(forbidden, script)
        self.assertIn('xattr -dr com.apple.quarantine "${STAGE}/Yisi.app"', script)

    def test_package_contains_identical_app_script_readme_and_checksum(self):
        output = self.directory / "assisted.zip"
        result = subprocess.run(["/bin/bash", str(ROOT / "scripts/package_assisted.sh"), str(self.app), str(output)],
                                cwd=ROOT, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            prefix = "Yisi-Assisted/"
            self.assertEqual(archive.read(prefix + "Yisi.app/Contents/MacOS/Yisi"), (self.app / "Contents/MacOS/Yisi").read_bytes())
            self.assertEqual(archive.read(prefix + "Install Yisi.command"), self.script.read_bytes())
            self.assertIn("READ ME.txt", " ".join(archive.namelist()))
            self.assertEqual(archive.read(prefix + "SHA256.txt"), self.manifest.read_bytes())
            self.assertTrue(archive.getinfo(prefix + "Install Yisi.command").external_attr >> 16 & 0o111)


if __name__ == "__main__":
    unittest.main()
