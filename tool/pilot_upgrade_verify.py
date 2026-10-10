"""Compare complete, externally captured QA artifacts with an expected manifest.

No ADB operations, device collection, or APK build is performed by this tool.
Native capture provenance requires review; a fixture receipt cannot release an APK.
"""
import argparse
from contextlib import closing
import base64
import hashlib
import json
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha(value, label):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value), label)


def same_json(left, right):
    # Python considers True == 1: persisted flags and typed values must not.
    options = {"sort_keys": True, "ensure_ascii": False, "allow_nan": False}
    return json.dumps(left, **options) == json.dumps(right, **options)


def safe_file(root, name):
    require(isinstance(name, str) and name and not Path(name).is_absolute(), "Relative artifact required")
    path = (root / name).resolve()
    require(path.is_relative_to(root.resolve()) and path.is_file() and not (root / name).is_symlink(),
            "Missing/unsafe artifact: " + name)
    return path


def db_contents(path):
    def identifier(value):
        return '"' + value.replace('"', '""') + '"'

    def scalar(value):
        if isinstance(value, bytes):
            return {"blobBase64": base64.b64encode(value).decode("ascii")}
        return value

    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)) as db:
        require(db.execute("pragma integrity_check").fetchall() == [("ok",)], "Invalid SQLite")
        names = [row[0] for row in db.execute(
            "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")]
        tables = {}
        for name in names:
            column_info = [list(row) for row in db.execute("pragma table_info(" + identifier(name) + ")")]
            cols = [row[1] for row in column_info]
            rows = [[scalar(v) for v in row] for row in db.execute(
                "select " + ",".join(map(identifier, cols)) + " from " + identifier(name))]
            # Preserve duplicates, while ignoring physical row/page ordering.
            rows.sort(key=lambda row: json.dumps(row, sort_keys=True, ensure_ascii=False))
            tables[name] = {"columns": cols, "columnInfo": column_info, "rows": rows}
        return {"schema": db.execute("pragma user_version").fetchone()[0], "tables": tables}


def inventory(root):
    require(root.is_dir(), "Missing capture directory")
    result = {}
    for path in sorted(root.rglob("*")):
        require(not path.is_symlink(), "Capture cannot contain symlinks")
        if path.is_file():
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def verify(manifest_path, before, after):
    manifest = read_json(manifest_path)
    require(manifest.get("format") == "seguimiento-pilot-manifest" and manifest.get("version") == 1,
            "Unknown manifest format/version")
    require(manifest.get("evidenceKind") in {"native_capture", "synthetic_fixture"}, "Evidence kind required")
    require(re.fullmatch(r"[0-9a-f]{40}", manifest.get("sourceSha", "")) is not None, "Source SHA required")
    require(re.fullmatch(r"[0-9a-f]{40}", manifest.get("baseSourceSha", "")) is not None, "Base source SHA required")
    require(isinstance(manifest.get("datasetId"), str) and manifest["datasetId"].strip(), "Dataset ID required")
    sha(manifest.get("apkSha256"), "APK SHA required")
    sha(manifest.get("baseApkSha256"), "Base APK SHA required")
    require(manifest.get("syntheticOnly") is True, "Only synthetic QA data allowed")
    device = manifest.get("device", {})
    require(re.fullmatch(r"emulator-\d+", device.get("serial", "")) is not None and
            isinstance(device.get("avd"), str) and bool(device["avd"]), "Own QA AVD identity required")
    phases = {"before": {"paused"}, "after": {"upgraded", "resumed", "reopened", "backup_restored"}}
    summaries = {}
    for stage, root in (("before", before), ("after", after)):
        expected = manifest[stage]
        expected_db = expected["database"]
        require(type(expected_db.get("schema")) is int and expected_db["schema"] > 0 and
                isinstance(expected_db.get("tables"), dict) and expected_db["tables"], "Full schema/tables required")
        actual_db = db_contents(safe_file(root, "seguimiento.sqlite"))
        require(same_json(actual_db, expected_db), "Database values/schema/columns/tables differ: " + stage)
        for filename, key in (("flags.json", "flags"), ("sesion-en-curso.json", "session")):
            require(isinstance(expected.get(key), dict) and expected[key], "Flags/session expectations required")
            require(same_json(read_json(safe_file(root, filename)), expected[key]), "JSON differs: " + stage + "/" + filename)
        photos = {name: value for name, value in inventory(root).items() if name.startswith("fotos/")}
        require(isinstance(expected.get("photos"), dict) and photos == expected["photos"], "Photo inventory differs: " + stage)
        for value in photos.values():
            sha(value, "Photo hash invalid")
        capture = read_json(safe_file(root, "capture.json"))
        require(capture.get("device") == device, "Captured QA device mismatch")
        require(capture.get("installed") == expected["installed"], "Installed package metadata mismatch")
        installed = capture["installed"]
        require(installed.get("package") == "com.juandiego.seguimiento", "Unexpected package")
        sha(installed.get("signatureSha256"), "Signature missing")
        require(type(installed.get("versionCode")) is int and installed["versionCode"] > 0 and
                type(installed.get("targetSdk")) is int and installed["targetSdk"] > 0 and
                isinstance(installed.get("versionName"), str) and installed["versionName"], "Incomplete package metadata")
        require(set(expected["phases"]) == phases[stage] and set(capture["phases"]) == phases[stage], "Required phases missing/extra")
        for phase in phases[stage]:
            oracle = expected["phases"][phase]
            execution = capture["phases"][phase]
            require(execution.get("exitCode") == 0 and type(execution.get("exitCode")) is int and
                    isinstance(execution.get("command"), list) and bool(execution["command"]) and
                    isinstance(execution.get("command")[0], str) and execution["command"][0], "Phase not executed: " + phase)
            require(execution.get("ui") == oracle["ui"] and execution.get("log") == oracle["log"], "Unexpected phase artifacts")
            log = safe_file(root, oracle["log"]).read_text(encoding="utf-8-sig")
            require(isinstance(oracle.get("logContains"), list) and oracle["logContains"] and
                    all(isinstance(v, str) and v and v in log for v in oracle["logContains"]), "Phase command log mismatch: " + phase)
            labels = [node.get("text", "") + "\n" + node.get("content-desc", "")
                      for node in ET.parse(safe_file(root, oracle["ui"])).iter("node")]
            joined = "\n".join(labels)
            require(isinstance(oracle.get("labels"), list) and oracle["labels"] and
                    all(isinstance(v, str) and v and v in joined for v in oracle["labels"]), "UI oracle differs: " + phase)
        summaries[stage] = {"schema": actual_db["schema"], "tables": len(actual_db["tables"]),
                            "rows": sum(len(t["rows"]) for t in actual_db["tables"].values()),
                            "artifacts": inventory(root)}
    require(manifest["before"]["installed"]["signatureSha256"] == manifest["after"]["installed"]["signatureSha256"],
            "Upgrade signature changed")
    require(manifest["after"]["installed"]["versionCode"] > manifest["before"]["installed"]["versionCode"], "Not an upgrade")
    return {"format": "seguimiento-pilot-receipt", "version": 1, "status": "MATCHED_CAPTURE",
            "evidenceKind": manifest["evidenceKind"], "syntheticOnly": True,
            "sourceSha": manifest["sourceSha"], "baseSourceSha": manifest["baseSourceSha"],
            "datasetId": manifest["datasetId"], "apkSha256": manifest["apkSha256"],
            "baseApkSha256": manifest["baseApkSha256"],
            "installed": manifest["after"]["installed"], "device": device,
            "inputs": {"manifest": str(manifest_path.resolve()), "before": str(before.resolve()), "after": str(after.resolve())},
            "manifestSha256": digest(manifest_path), "captures": summaries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("manifest", "before", "after", "receipt"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    # A failed rerun cannot leave a stale approved receipt at the requested path.
    try:
        result = verify(args.manifest, args.before, args.after)
        require(args.receipt.resolve() not in {args.manifest.resolve()}, "Receipt cannot overwrite manifest")
        require(not args.receipt.resolve().is_relative_to(args.before.resolve()) and
                not args.receipt.resolve().is_relative_to(args.after.resolve()), "Receipt must be outside captures")
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.receipt.with_suffix(args.receipt.suffix + ".partial")
        temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(args.receipt)
        print(json.dumps({"status": result["status"], "evidenceKind": result["evidenceKind"]}))
        return 0
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error, ET.ParseError) as error:
        # Never remove an input file for an incorrectly chosen output path.
        path = args.receipt.resolve()
        if path != args.manifest.resolve() and not path.is_relative_to(args.before.resolve()) and not path.is_relative_to(args.after.resolve()):
            args.receipt.unlink(missing_ok=True)
        print("REJECTED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
