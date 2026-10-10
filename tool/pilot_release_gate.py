"""Fail closed unless APK metadata, source and re-read QA evidence match.

Requires Android SDK aapt and apksigner; absence is a failure, not a hash-only pass.
Never builds, signs, installs, or publishes. Synthetic fixtures cannot authorize release.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from pilot_upgrade_verify import digest, read_json, require, verify


def sdk_tool(name, override):
    if override:
        require(override.is_file(), "Missing metadata tool: " + str(override))
        return str(override)
    found = shutil.which(name)
    if found:
        return found
    suffix = ".exe" if name == "aapt" and os.name == "nt" else ".bat" if os.name == "nt" else ""
    for root in (os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME"),
                 str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk")):
        if root:
            candidates = sorted((Path(root) / "build-tools").glob("*/" + name + suffix), reverse=True)
            if candidates:
                return str(candidates[0])
    raise ValueError("Missing Android metadata tool: " + name)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30, shell=False)
    require(result.returncode == 0, "Metadata command failed: " + Path(command[0]).name)
    return result.stdout


def inspect_apk(apk, aapt=None, apksigner=None):
    badging = run([sdk_tool("aapt", aapt), "dump", "badging", str(apk.resolve())])
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    target = re.search(r"^targetSdkVersion:'(\d+)'", badging, re.M)
    signature = run([sdk_tool("apksigner", apksigner), "verify", "--verbose", "--print-certs", str(apk.resolve())])
    # Android build-tools differ: newer output says Signer #1, older V2 Signer.
    certificates = set(value.lower() for value in re.findall(
        r"^(?:Signer #\d+|V[1-4] Signer:) certificate SHA-256 digest: ([0-9a-fA-F]{64})$", signature, re.M))
    require(package and target and len(certificates) == 1, "Incomplete/ambiguous APK identity")
    return {"package": package[1], "versionCode": int(package[2]), "versionName": package[3],
            "targetSdk": int(target[1]), "signatureSha256": next(iter(certificates))}


def validate(apk, receipt_path, source_sha, inspector=inspect_apk):
    require(re.fullmatch(r"[0-9a-f]{40}", source_sha) is not None, "Exact source SHA required")
    receipt = read_json(receipt_path)
    require(receipt.get("format") == "seguimiento-pilot-receipt" and receipt.get("version") == 1 and
            receipt.get("status") == "MATCHED_CAPTURE", "Invalid receipt")
    require(receipt.get("evidenceKind") == "native_capture", "Synthetic fixture is not native release evidence")
    require(receipt.get("sourceSha") == source_sha, "Receipt belongs to another source")
    require(receipt.get("apkSha256") == digest(apk), "APK bytes changed")
    inputs = receipt["inputs"]
    fresh = verify(Path(inputs["manifest"]), Path(inputs["before"]), Path(inputs["after"]))
    require(receipt == fresh, "Receipt/captured evidence changed")
    require(inspector(apk) == receipt["installed"], "Independent APK metadata differs")
    return {"status": "MATCHED_APK_AND_CAPTURE", "sourceSha": source_sha, "apkSha256": receipt["apkSha256"],
            "installed": receipt["installed"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--aapt", type=Path)
    parser.add_argument("--apksigner", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.apk, args.receipt, args.source_sha,
                          lambda apk: inspect_apk(apk, args.aapt, args.apksigner))
        import json
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print("REJECTED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
