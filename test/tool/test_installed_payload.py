"""Synthetic exact installed-file checks; no application installation or launch."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

HELPER = Path(__file__).resolve().parents[2] / "tool/release/lifecycle/verify_installed_payload.py"
SPEC = importlib.util.spec_from_file_location("bsl_installed_payload", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InstalledPayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bsl-installed-payload-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.current = self.root / "install/current"
        self.current.mkdir(parents=True)
        self.package = self.root / "full.nupkg"
        self.entries = {
            "lib/app/BlackSpiritLife.exe": b"main",
            "lib/app/BlackSpiritLife_ExecutionStub.exe": b"stub",
            "lib/app/Squirrel.exe": b"updater",
            "lib/app/sq.version": b"<package><version>1.2.3</version></package>",
            "lib/app/data/hidden/.marker": b"hidden asset",
            "lib/app/data/catalog.json": b"reference",
            "BlackSpiritLife.App.nuspec": b"metadata",
        }
        self.write_package()
        for name, data in self.entries.items():
            if not name.startswith(MODULE.PREFIX):
                continue
            relative = name[len(MODULE.PREFIX):]
            dest = self.current.parent / MODULE.RELOCATED[relative] if relative in MODULE.RELOCATED else self.current / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)

    def write_package(self, extra=()):
        with zipfile.ZipFile(self.package, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)
            for name, data in extra:
                archive.writestr(name, data)
        self.sha256 = hashlib.sha256(self.package.read_bytes()).hexdigest()

    def verify(self):
        return MODULE.verify(self.package, self.sha256, self.current)

    def test_complete_exact_payload_and_relocated_tools(self):
        result = self.verify()
        self.assertTrue(result["success"])
        self.assertEqual(result["expectedInventorySha256"], result["installedInventorySha256"])
        self.assertEqual(result["expectedFileCount"], 6)
        self.assertEqual(result["excludedCurrentFiles"], [])
        self.assertNotIn(str(self.root), json.dumps(result))

    def test_hidden_missing_asset_detected(self):
        (self.current / "data/hidden/.marker").unlink()
        result = self.verify()
        self.assertFalse(result["success"])
        self.assertEqual(result["missing"], ["current/data/hidden/.marker"])

    def test_extra_managed_file_rejected(self):
        (self.current / "stale.exe").write_bytes(b"old application")
        self.assertEqual(self.verify()["unexpected"], ["current/stale.exe"])

    def test_changed_same_length_file_detected(self):
        (self.current / "BlackSpiritLife.exe").write_bytes(b"evil")
        self.assertEqual(self.verify()["changed"], ["current/BlackSpiritLife.exe"])

    def test_control_manifest_is_not_ignored(self):
        (self.current / "sq.version").write_bytes(b"incorrect version")
        self.assertEqual(self.verify()["changed"], ["current/sq.version"])

    def test_relocated_updater_checked(self):
        (self.current.parent / "Update.exe").write_bytes(b"wrong updater")
        self.assertEqual(self.verify()["changed"], ["root/Update.exe"])

    def test_relocated_stub_required(self):
        (self.current.parent / "BlackSpiritLife.exe").unlink()
        self.assertEqual(self.verify()["missing"], ["root/BlackSpiritLife.exe"])

    def test_mutable_install_root_is_separate_scope(self):
        (self.current.parent / "update.log").write_bytes(b"ordinary control log")
        self.assertTrue(self.verify()["success"])

    def test_wrong_package_hash_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
            MODULE.verify(self.package, "0" * 64, self.current)

    def test_archive_traversal_ads_reserved_aliases(self):
        for name in ("../outside", "lib/app/file:stream", "lib/app/NUL", "lib/app/a./file", "/rooted"):
            with self.subTest(name=name):
                self.write_package(((name, b"unsafe"),))
                with self.assertRaises(RuntimeError):
                    self.verify()

    def test_case_alias_implicit_parent(self):
        self.write_package((("lib/app/Data/other", b"case alias"),))
        with self.assertRaisesRegex(RuntimeError, "implicit parent"):
            self.verify()

    def test_file_directory_alias(self):
        self.write_package((("lib/app/data", b"file where parent directory exists"),))
        with self.assertRaises(RuntimeError):
            self.verify()

    def test_unreviewed_stub_layout_rejected(self):
        self.write_package((("lib/app/Nested_ExecutionStub.exe", b"stub"),))
        with self.assertRaisesRegex(RuntimeError, "unreviewed relocated"):
            self.verify()

    def test_encoded_symlink_rejected(self):
        self.write_package((("lib/app/something.__symlink", b"../outside"),))
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            self.verify()

    def test_unix_symlink_archive_rejected(self):
        info = zipfile.ZipInfo("lib/app/linked")
        info.create_system = 3
        info.external_attr = 0o120777 << 16
        self.write_package(((info, b"../outside"),))
        with self.assertRaisesRegex(RuntimeError, "symbolic-link"):
            self.verify()

    def test_unsupported_prefix_is_not_silently_omitted(self):
        self.write_package((("lib/net45/forgotten.dll", b"payload"),))
        with self.assertRaisesRegex(RuntimeError, "unsupported package payload prefix"):
            self.verify()

    def test_missing_required_package_control(self):
        del self.entries["lib/app/sq.version"]
        self.write_package()
        with self.assertRaisesRegex(RuntimeError, "required application/control"):
            self.verify()

    def test_installed_reparse_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = self.current / "linked"
        if os.name == "nt":
            completed = subprocess.run(["cmd.exe", "/d", "/c", "mklink", "/J", str(link), str(outside)], capture_output=True)
            self.assertEqual(completed.returncode, 0, "Synthetic junction fixture must be available")
        else:
            link.symlink_to(outside, target_is_directory=True)
        try:
            with self.assertRaisesRegex(RuntimeError, "reparse"):
                self.verify()
        finally:
            if os.name == "nt":
                link.rmdir()
            else:
                link.unlink()

    def test_changes_during_inventory_rejected(self):
        original = MODULE.file_record
        changed = False
        def mutating_record(path, logical):
            nonlocal changed
            result = original(path, logical)
            if not changed:
                (self.current / "arrived-late.txt").write_bytes(b"late")
                changed = True
            return result
        MODULE.file_record = mutating_record
        try:
            with self.assertRaisesRegex(RuntimeError, "tree changed"):
                self.verify()
        finally:
            MODULE.file_record = original

    def test_cli_atomic_new_report_and_no_overwrite(self):
        report = self.root / "report.json"
        command = [sys.executable, "-I", "-E", "-B", str(HELPER), "--package", str(self.package), "--approved-package-sha256", self.sha256,
                   "--installed-current", str(self.current), "--output", str(report)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        original = report.read_bytes()
        self.assertTrue(json.loads(original)["success"])
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(report.read_bytes(), original)
        self.assertEqual(list(self.root.glob("*.partial-*")), [])

    def test_failed_comparison_reports_nonzero_and_not_success(self):
        (self.current / "BlackSpiritLife.exe").write_bytes(b"wrong")
        report = self.root / "failed.json"
        result = subprocess.run([sys.executable, "-I", "-E", "-B", str(HELPER), "--package", str(self.package), "--approved-package-sha256", self.sha256,
                                 "--installed-current", str(self.current), "--output", str(report)], capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(report.read_text())["success"])

    def test_optimized_python_not_allowed(self):
        result = subprocess.run([sys.executable, "-I", "-E", "-O", str(HELPER)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("assertions to be enabled", result.stderr)


if __name__ == "__main__":
    unittest.main()
