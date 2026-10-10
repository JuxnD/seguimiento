"""Fictitious captures test the verifier; they do not prove Android execution."""
import copy
from contextlib import closing
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import pilot_upgrade_verify as upgrade
import pilot_release_gate as gate


class PilotGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="seguimiento_pilot_fixture_")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.before, self.after = self.root / "before", self.root / "after"
        self.apk, self.manifest_path, self.receipt_path = [self.root / n for n in ("fake.apk", "manifest.json", "receipt.json")]
        self.apk.write_bytes(b"FICTITIOUS APK: never install or distribute")
        self.device = {"serial": "emulator-5580", "avd": "FICTITIOUS_QA"}
        installed = {"package": "com.juandiego.seguimiento", "versionCode": 29,
                     "versionName": "1.21.0", "targetSdk": 34, "signatureSha256": "f" * 64}
        self.manifest = {"format": "seguimiento-pilot-manifest", "version": 1,
                         "evidenceKind": "synthetic_fixture", "syntheticOnly": True,
                         "sourceSha": "a" * 40, "baseSourceSha": "b" * 40,
                         "apkSha256": upgrade.digest(self.apk), "baseApkSha256": "d" * 64,
                         "datasetId": "FICTITIOUS_012", "device": self.device}
        for stage, root, names in (("before", self.before, ["paused"]),
                                   ("after", self.after, ["upgraded", "resumed", "reopened", "backup_restored"])):
            root.mkdir()
            with closing(sqlite3.connect(root / "seguimiento.sqlite")) as db:
                db.execute("pragma user_version=20")
                db.execute("create table observations(id integer, value real, detail text)")
                db.execute("insert into observations values(1, 72.5, 'FICTICIO')")
                db.commit()
            photos = root / "fotos"
            photos.mkdir()
            (photos / "fixture.jpg").write_bytes(b"FAKE PHOTO")
            flags, session = {"asked": True}, {"index": 7, "dose": 6}
            for file, values in (("flags.json", flags), ("sesion-en-curso.json", session)):
                self.write(root / file, values)
            actual_installed = dict(installed)
            if stage == "after":
                actual_installed.update(versionCode=30, versionName="1.22.0")
            phase_oracles, executions = {}, {}
            for name in names:
                ui, log = name + ".xml", name + ".log"
                (root / ui).write_text('<hierarchy><node text="SERIE 2/2" content-desc="6 reps" /></hierarchy>')
                (root / log).write_text("FICTITIOUS phase " + name + " success")
                phase_oracles[name] = {"ui": ui, "log": log, "labels": ["SERIE 2/2", "6 reps"],
                                       "logContains": ["phase " + name + " success"]}
                executions[name] = {"ui": ui, "log": log, "exitCode": 0, "command": ["FICTITIOUS", name]}
            self.write(root / "capture.json", {"device": self.device, "installed": actual_installed, "phases": executions})
            self.manifest[stage] = {"database": upgrade.db_contents(root / "seguimiento.sqlite"),
                                    "installed": actual_installed, "flags": flags, "session": session,
                                    "photos": {"fotos/fixture.jpg": upgrade.digest(photos / "fixture.jpg")}, "phases": phase_oracles}
        self.write_manifest()

    def write(self, file, data):
        file.write_text(json.dumps(data), encoding="utf-8")

    def write_manifest(self):
        self.write(self.manifest_path, self.manifest)

    def verify(self):
        return upgrade.verify(self.manifest_path, self.before, self.after)

    def mock_native_receipt(self):
        # Internal mock exercise only. The public CLI refuses ordinary fixtures.
        self.manifest["evidenceKind"] = "native_capture"
        self.write_manifest()
        self.write(self.receipt_path, self.verify())

    def validate(self, metadata=None):
        return gate.validate(self.apk, self.receipt_path, "a" * 40,
                             lambda _: metadata or self.manifest["after"]["installed"])

    def test_positive_artifact_comparison_cli(self):
        result = subprocess.run([sys.executable, str(Path(upgrade.__file__)), "--manifest", str(self.manifest_path),
                                 "--before", str(self.before), "--after", str(self.after), "--receipt", str(self.receipt_path)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(upgrade.read_json(self.receipt_path), self.verify())

    def test_release_refuses_synthetic_fixture_cli(self):
        self.write(self.receipt_path, self.verify())
        result = subprocess.run([sys.executable, str(Path(gate.__file__)), "--apk", str(self.apk),
                                 "--receipt", str(self.receipt_path), "--source-sha", "a" * 40],
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Synthetic fixture", result.stderr)

    def test_mocked_metadata_positive_not_native_qa(self):
        self.mock_native_receipt()
        self.assertEqual(self.validate()["status"], "MATCHED_APK_AND_CAPTURE")

    def test_changed_apk_byte_rejected(self):
        self.mock_native_receipt()
        self.apk.write_bytes(self.apk.read_bytes() + b"X")
        with self.assertRaisesRegex(ValueError, "APK bytes"):
            self.validate()

    def test_wrong_source_rejected(self):
        self.mock_native_receipt()
        with self.assertRaisesRegex(ValueError, "another source"):
            gate.validate(self.apk, self.receipt_path, "c" * 40)

    def test_wrong_independent_signature_rejected(self):
        self.mock_native_receipt()
        metadata = dict(self.manifest["after"]["installed"], signatureSha256="e" * 64)
        with self.assertRaisesRegex(ValueError, "metadata"):
            self.validate(metadata)

    def test_tampered_receipt_rejected(self):
        self.mock_native_receipt()
        receipt = upgrade.read_json(self.receipt_path)
        receipt["captures"]["after"]["rows"] = 0
        self.write(self.receipt_path, receipt)
        with self.assertRaisesRegex(ValueError, "evidence changed"):
            self.validate()

    def test_missing_receipt_rejected(self):
        with self.assertRaises(FileNotFoundError):
            self.validate()

    def test_mutant_value_schema_tables_columns_and_duplicates(self):
        original = (self.after / "seguimiento.sqlite").read_bytes()
        for sql in ("update observations set value=0", "pragma user_version=21",
                    "create table unexpected(id integer)", "alter table observations add column extra text",
                    "insert into observations select * from observations"):
            with self.subTest(sql=sql):
                (self.after / "seguimiento.sqlite").write_bytes(original)
                with closing(sqlite3.connect(self.after / "seguimiento.sqlite")) as db:
                    db.execute(sql)
                    db.commit()
                with self.assertRaisesRegex(ValueError, "Database"):
                    self.verify()

    def test_mutant_photo_missing_changed_extra(self):
        photo = self.after / "fotos/fixture.jpg"
        original = photo.read_bytes()
        photo.unlink()
        with self.assertRaisesRegex(ValueError, "Photo"):
            self.verify()
        photo.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Photo"):
            self.verify()
        photo.write_bytes(original)
        (self.after / "fotos/unexpected.jpg").write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "Photo"):
            self.verify()

    def test_mutant_flags_session_ui_log_and_unexecuted_phase(self):
        for file, content in (("flags.json", '{"asked":false}'), ("sesion-en-curso.json", '{"index":8}'),
                              ("flags.json", '{"asked":1}'),
                              ("reopened.xml", '<hierarchy><node text="wrong dose" /></hierarchy>'),
                              ("upgraded.log", "failure")):
            with self.subTest(file=file):
                path = self.after / file
                old = path.read_bytes()
                path.write_text(content)
                with self.assertRaises(ValueError):
                    self.verify()
                path.write_bytes(old)
        capture = upgrade.read_json(self.after / "capture.json")
        capture["phases"]["resumed"]["exitCode"] = 1
        self.write(self.after / "capture.json", capture)
        with self.assertRaisesRegex(ValueError, "not executed"):
            self.verify()

    def test_missing_or_empty_required_manifest_fields(self):
        original = copy.deepcopy(self.manifest)
        for field in ("sourceSha", "baseSourceSha", "evidenceKind", "syntheticOnly", "datasetId", "apkSha256", "baseApkSha256"):
            with self.subTest(field=field):
                self.manifest = copy.deepcopy(original)
                del self.manifest[field]
                self.write_manifest()
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    self.verify()

    def test_missing_phase_and_changed_upgrade_signature(self):
        capture_file = self.after / "capture.json"
        capture = upgrade.read_json(capture_file)
        old = copy.deepcopy(capture)
        del capture["phases"]["resumed"]
        self.write(capture_file, capture)
        with self.assertRaisesRegex(ValueError, "phases"):
            self.verify()
        old["installed"]["signatureSha256"] = "c" * 64
        self.manifest["after"]["installed"]["signatureSha256"] = "c" * 64
        self.write(capture_file, old)
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "signature changed"):
            self.verify()

    def test_changed_manifest_after_receipt_rejected(self):
        self.mock_native_receipt()
        self.manifest["datasetId"] = "OTHER"
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "evidence changed"):
            self.validate()

    def test_stale_receipt_removed_on_failed_cli_rerun(self):
        self.write(self.receipt_path, self.verify())
        (self.after / "reopened.xml").unlink()
        result = subprocess.run([sys.executable, str(Path(upgrade.__file__)), "--manifest", str(self.manifest_path),
                                 "--before", str(self.before), "--after", str(self.after), "--receipt", str(self.receipt_path)],
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.receipt_path.exists())

    def test_missing_metadata_tool_is_not_hash_only_pass(self):
        self.mock_native_receipt()
        with self.assertRaisesRegex(ValueError, "Missing metadata tool"):
            gate.inspect_apk(self.apk, aapt=self.root / "absent-aapt")

    def test_metadata_parsing_uses_both_tools_and_timeout(self):
        badging = "package: name='com.juandiego.seguimiento' versionCode='30' versionName='1.22.0'\ntargetSdkVersion:'34'\n"
        for prefix in ("Signer #1", "V2 Signer:"):
            signer = prefix + " certificate SHA-256 digest: " + "f" * 64 + "\n"
            with self.subTest(prefix=prefix), patch.object(gate, "sdk_tool", side_effect=lambda name, _: name), patch.object(gate, "run", side_effect=[badging, signer]) as runner:
                self.assertEqual(gate.inspect_apk(self.apk), self.manifest["after"]["installed"])
                self.assertEqual(runner.call_count, 2)
        ambiguous = "Signer #1 certificate SHA-256 digest: " + "f" * 64 + "\nSigner #2 certificate SHA-256 digest: " + "e" * 64 + "\n"
        with patch.object(gate, "sdk_tool", side_effect=lambda name, _: name), patch.object(gate, "run", side_effect=[badging, ambiguous]):
            with self.assertRaisesRegex(ValueError, "ambiguous"):
                gate.inspect_apk(self.apk)
        with patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as process:
            gate.run(["tool", "arg"])
            self.assertEqual(process.call_args.kwargs["timeout"], 30)
            self.assertFalse(process.call_args.kwargs["shell"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
