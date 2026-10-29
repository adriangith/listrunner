#!/usr/bin/env python3
"""Verify that a built app contains every canonical JSON resource unchanged."""

import hashlib
from pathlib import Path
import sys


def verify_resources(source: Path, app: Path) -> list[str]:
    resources = sorted(source.glob("*.json"))
    errors = []
    if not resources:
        errors.append(f"No canonical JSON resources found in {source}")
    if not app.is_dir():
        errors.append(f"App bundle not found: {app}")
        return errors
    for resource in resources:
        bundled = app / resource.name
        if not bundled.is_file():
            errors.append(f"Missing bundled resource: {resource.name}")
        elif hashlib.sha256(bundled.read_bytes()).digest() != hashlib.sha256(resource.read_bytes()).digest():
            errors.append(f"Bundled resource differs from canonical file: {resource.name}")
    for duplicate in sorted(app.rglob("*-v2.json")):
        errors.append(f"Duplicate legacy resource bundled: {duplicate.relative_to(app)}")
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 verify-bundled-resources.py <path/to/ListRunner.app>", file=sys.stderr)
        return 2
    source = Path(__file__).resolve().parents[1] / "ListRunner" / "Resources"
    errors = verify_resources(source, Path(sys.argv[1]))
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"PASS: all {len(list(source.glob('*.json')))} bundled JSON resources match canonical files; no legacy -v2 resources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
