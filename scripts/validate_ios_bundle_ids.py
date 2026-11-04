#!/usr/bin/env python3
"""Reject duplicate identifiers before an IPA reaches an iPhone installer."""
import plistlib
import sys
from pathlib import Path


def validate(app: Path) -> None:
    if not (app / "Info.plist").is_file():
        raise SystemExit(f"Missing app Info.plist: {app}")
    seen = {}
    for plist in sorted(app.rglob("Info.plist")):
        with plist.open("rb") as stream:
            info = plistlib.load(stream)
        identifier = info.get("CFBundleIdentifier")
        if not identifier:
            continue
        if identifier in seen:
            raise SystemExit(f"Duplicate bundle ID {identifier}: {seen[identifier]} and {plist}")
        seen[identifier] = plist
    print(f"Validated {len(seen)} unique bundle identifiers")


if __name__ == "__main__":
    validate(Path(sys.argv[1]))
