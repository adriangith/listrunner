#!/usr/bin/env python3
"""Audit the cloud archive and print release provenance into its build log."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def audit(archive: Path) -> dict:
    base = Path(__file__).resolve().parents[1]
    apps = list((archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one archived application")
    app = apps[0]
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.adrianzafir.listrunner":
        raise ValueError("Unexpected archived bundle identifier")
    version = info.get("CFBundleShortVersionString", "")
    build = info.get("CFBundleVersion", "")
    if not version or "$" in version or not str(build).isdigit() or int(build) < 1:
        raise ValueError("Missing or unresolved archived version/build")
    spec = importlib.util.spec_from_file_location("resources", base / "tests/verify-bundled-resources.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    errors = verifier.verify_resources(base / "ListRunner/Resources", app)
    if errors:
        raise ValueError("; ".join(errors))
    commit = subprocess.check_output(["git", "-C", str(base), "rev-parse", "HEAD"], text=True).strip()
    return {
        "sourceCommit": commit,
        "cloudBuildNumber": os.environ.get("CI_BUILD_NUMBER"),
        "bundleIdentifier": info["CFBundleIdentifier"],
        "archiveVersion": version,
        "archiveBuild": build,
        "canonicalResources": len(list((base / "ListRunner/Resources").glob("*.json"))),
        "status": "archive-resources-verified-not-upload-confirmation",
    }


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: verify-cloud-archive.py <archive.xcarchive>")
        print(json.dumps(audit(Path(sys.argv[1])), indent=2))
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"error: Cloud archive audit failed: {error}", file=sys.stderr)
        sys.exit(1)
