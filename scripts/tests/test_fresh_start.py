"""Exercise startup/reset decisions with mocked macOS commands, never real user data."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fresh-start.sh"

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, shutil, subprocess, sys
root = pathlib.Path(os.environ["YISI_SCRIPT_TEST_ROOT"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "events.jsonl").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "uname":
    print("Darwin")
elif name == "ps":
    if (root / "running").exists():
        executable = str(root / "repo with spaces/build-app/Debug/Yisi.app/Contents/MacOS/Yisi")
        print(executable if "comm=" in args and "pid=" not in args else "999999 " + executable)
elif name == "swift":
    if args and args[0].endswith("keep-keys.swift"):
        sys.exit(subprocess.call(["/usr/bin/swift", "-module-cache-path", str(root / "swift-module-cache"), *args]))
    if "--show-bin-path" in args:
        print(root / "bin")
    elif os.environ.get("YISI_SCRIPT_TEST_BUILD_FAIL") == "1":
        print("mock build failure")
        sys.exit(1)
    else:
        print("mock build successful")
elif name == "tee":
    sys.stdout.write(sys.stdin.read())
elif name == "mkdir":
    for arg in args:
        if not arg.startswith("-") and pathlib.Path(arg).is_relative_to(root):
            pathlib.Path(arg).mkdir(parents=True, exist_ok=True)
elif name == "rm":
    for arg in args:
        if not arg.startswith("-") and pathlib.Path(arg).is_relative_to(root):
            path = pathlib.Path(arg)
            if path.is_dir(): shutil.rmtree(path)
            elif path.exists(): path.unlink()
elif name == "defaults":
    if args[0] == "export":
        values = {"openai_api_key": "fake-primary-key", "api_provider": "OpenAI", "saved_presets": "must not survive"}
        if args[1] != "com.sonianmu.yisi":
            values = {"openai_api_key": "fake-legacy-key", "image_gemini_api_key": "fake-image-key"}
        pathlib.Path(args[2]).write_bytes(plistlib.dumps(values))
    elif args[0] == "import":
        if os.environ.get("YISI_SCRIPT_TEST_IMPORT_FAIL") == "1": sys.exit(1)
        shutil.copyfile(args[2], root / "retained.plist")
elif name == "security":
    deleted = root / "keychain-deleted"
    if deleted.exists(): sys.exit(44)
    deleted.touch()
elif name == "open":
    (root / "running").touch()
elif name == "tccutil":
    if os.environ.get("YISI_SCRIPT_TEST_TCC_MISSING") == "1":
        print('tccutil: No such bundle identifier "com.sonianmu.yisi": OSStatus error -10814.', file=sys.stderr)
        sys.exit(1)
    if os.environ.get("YISI_SCRIPT_TEST_TCC_FAIL") == "1":
        print('tccutil: Operation not permitted', file=sys.stderr)
        sys.exit(1)
elif name == "lsregister" and os.environ.get("YISI_SCRIPT_TEST_REGISTER_FAIL") == "1":
    sys.exit(1)
# codesign, successful lsregister and touch only record the intended calls.
'''


class FreshStartTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yisi-script-tests-")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo with spaces"
        (self.repo / "scripts").mkdir(parents=True)
        self.script = self.repo / "scripts/fresh-start.sh"
        shutil.copyfile(SCRIPT, self.script)
        self.script.chmod(0o755)
        (self.root / "bin").mkdir()
        binary = self.root / "bin/Yisi"
        binary.write_text("mock executable")
        binary.chmod(0o755)
        (self.root / "tmp").mkdir()
        stubs = self.root / "stubs"
        stubs.mkdir()
        mock = stubs / "mock.py"
        mock.write_text(MOCK)
        mock.chmod(0o755)
        for name in ["uname", "ps", "swift", "tee", "mkdir", "rm", "defaults", "security", "codesign", "tccutil", "open", "touch", "lsregister"]:
            (stubs / name).symlink_to(mock)
        self.script.write_text(self.script.read_text().replace(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            str(stubs / "lsregister")))
        self.env = dict(os.environ, PATH=f"{stubs}:{os.environ['PATH']}",
                        TMPDIR=str(self.root / "tmp"), YISI_SCRIPT_TEST_ROOT=str(self.root))

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, *args, **environment):
        return subprocess.run(["/bin/bash", str(self.script), *args], cwd="/tmp",
                              env=dict(self.env, **environment), text=True, capture_output=True)

    def events(self):
        path = self.root / "events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_help_and_invalid_argument_combinations(self):
        self.assertEqual(self.run_script("--help").returncode, 0)
        for args in [(), ("--invalid",), ("--start", "--close"), ("--close", "--keep-keys"), ("--start", "--keep-permissions")]:
            self.assertEqual(self.run_script(*args).returncode, 2, args)

    def test_every_mode_supports_side_effect_free_dry_run(self):
        for mode in ["--close", "--start", "--new"]:
            result = self.run_script(mode, "--dry-run")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(event[0] not in ["uname"] for event in self.events()))
        self.assertFalse((self.repo / "build-app").exists())

    def test_close_with_no_app_does_not_reset_or_build(self):
        self.assertEqual(self.run_script("--close").returncode, 0)
        self.assertEqual({event[0] for event in self.events()}, {"uname", "ps"})

    def test_start_packages_current_binary_without_resetting(self):
        result = self.run_script("--start")
        self.assertEqual(result.returncode, 0, result.stderr)
        app = self.repo / "build-app/Debug/Yisi.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.sonianmu.yisi")
        self.assertIn("NSScreenCaptureUsageDescription", info)
        self.assertTrue((app / "Contents/MacOS/Yisi").is_file())
        names = {event[0] for event in self.events()}
        self.assertIn("codesign", names)
        self.assertIn("open", names)
        launch = next(event for event in self.events() if event[0] == "open")
        self.assertIn("-n", launch)
        self.assertIn(str(app), launch)
        self.assertFalse(names & {"defaults", "security", "tccutil"})

    def test_start_does_not_rebuild_an_already_running_app(self):
        (self.root / "running").touch()
        self.assertEqual(self.run_script("--start").returncode, 0)
        self.assertFalse(any(event[0] in ["swift", "open"] for event in self.events()))

    def test_start_retires_old_generated_bundle_before_registration(self):
        legacy = self.repo / ".build_app/Debug/Yisi.app"
        legacy.mkdir(parents=True)
        (legacy / "marker").write_text("old build")
        result = self.run_script("--start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(legacy.exists())
        archives = list((self.repo / ".build_app").glob("retired.*/Yisi.app.disabled/marker"))
        self.assertEqual(len(archives), 1)
        self.assertEqual(archives[0].read_text(), "old build")
        registrations = [event for event in self.events() if event[0] == "lsregister"]
        self.assertEqual(registrations, [
            ["lsregister", "-u", str(legacy)],
            ["lsregister", "-f", str(self.repo / "build-app/Debug/Yisi.app")]
        ])

    def test_new_build_failure_leaves_data_and_permissions_untouched(self):
        result = self.run_script("--new", YISI_SCRIPT_TEST_BUILD_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(event[0] in ["defaults", "rm", "security", "tccutil", "open"] for event in self.events()))

    def test_new_preserves_both_key_formats_but_resets_other_preferences(self):
        result = self.run_script("--new", "--keep-keys", "--keep-permissions")
        self.assertEqual(result.returncode, 0, result.stderr)
        retained = plistlib.loads((self.root / "retained.plist").read_bytes())
        self.assertEqual(retained, {"openai_api_key": "fake-primary-key", "image_gemini_api_key": "fake-image-key"})
        events = self.events()
        self.assertFalse(any(event[0] in ["security", "tccutil"] for event in events))
        self.assertLess(next(i for i, event in enumerate(events) if event[:2] == ["defaults", "import"]),
                        next(i for i, event in enumerate(events) if event[0] == "rm"))

    def test_failed_key_restoration_retains_private_backup_and_stops(self):
        result = self.run_script("--new", "--keep-keys", "--keep-permissions", YISI_SCRIPT_TEST_IMPORT_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        backups = list((self.root / "tmp").glob("*/api-keys.plist"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
        self.assertFalse(any(event[0] in ["security", "tccutil", "open"] for event in self.events()))

    def test_new_clears_only_yisi_state_and_scopes_permission_reset(self):
        result = self.run_script("--new")
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertEqual([event[2:] for event in events if event[:2] == ["tccutil", "reset"]],
                         [[kind, "com.sonianmu.yisi"] for kind in ["Accessibility", "ListenEvent", "PostEvent", "ScreenCapture"]])
        removed = [path for event in events if event[0] == "rm" for path in event[1:]]
        self.assertTrue(any(path.endswith("/Documents/HistoryImages") for path in removed))
        self.assertTrue(any(path.endswith("/Documents/YisiHistory.sqlite") for path in removed))
        self.assertFalse(any(path.startswith("/Applications/") for path in removed))
        self.assertTrue(any(event[0] == "open" for event in events))

    def test_app_registration_precedes_permission_reset(self):
        result = self.run_script("--new")
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(next(i for i, event in enumerate(events) if event[0] == "lsregister"),
                        next(i for i, event in enumerate(events) if event[0] == "tccutil"))
        self.assertLess(next(i for i, event in enumerate(events) if event[0] == "tccutil"),
                        next(i for i, event in enumerate(events) if event[:2] == ["defaults", "delete"]))

    def test_first_run_missing_bundle_id_does_not_block_launch(self):
        result = self.run_script("--new", YISI_SCRIPT_TEST_TCC_MISSING="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("跳过本次系统授权重置", result.stderr)
        self.assertTrue(any(event[0] == "open" for event in self.events()))

    def test_other_permission_errors_stop_before_clearing_data(self):
        result = self.run_script("--new", YISI_SCRIPT_TEST_TCC_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Operation not permitted", result.stderr)
        self.assertFalse(any(event[0] in ["defaults", "rm", "security", "open"] for event in self.events()))

    def test_registration_failure_stops_before_resetting_or_clearing(self):
        result = self.run_script("--new", YISI_SCRIPT_TEST_REGISTER_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(event[0] in ["defaults", "rm", "security", "tccutil", "open"] for event in self.events()))


if __name__ == "__main__":
    unittest.main()
