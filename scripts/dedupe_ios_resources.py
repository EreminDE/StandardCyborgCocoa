#!/usr/bin/env python3
"""Remove redundant nested SwiftPM resource bundles before iOS IPA packaging.

Xcode sometimes copies a SwiftPM resource bundle both into the .app root and
into a dynamic PackageProduct.framework. iOS installd rejects duplicate
CFBundleIdentifiers inside one app. Keep the root-level copy, where SwiftPM's
Bundle.module normally searches, and remove only an identical nested copy.
Never change executable framework identifiers or modify a non-identical bundle.
"""
import argparse
import hashlib
import plistlib
import shutil
from pathlib import Path


def bundle_identifier(bundle: Path) -> str | None:
    plist_path = bundle / "Info.plist"
    if not plist_path.is_file():
        return None
    with plist_path.open("rb") as stream:
        return plistlib.load(stream).get("CFBundleIdentifier")


def content_hashes(bundle: Path) -> dict[str, str]:
    files = {}
    for path in bundle.rglob("*"):
        if path.is_file():
            name = path.relative_to(bundle).as_posix()
            files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return files


def deduplicate_resource_bundles(app: Path) -> None:
    if not app.is_dir() or not (app / "Info.plist").is_file():
        raise SystemExit(f"Not a valid .app bundle: {app}")

    resource_bundles = {}
    for bundle in app.glob("*.bundle"):
        identity = bundle_identifier(bundle)
        if identity:
            if identity in resource_bundles:
                raise SystemExit(f"Two root resource bundles have the same ID: {identity}")
            resource_bundles[identity] = bundle

    framework_dir = app / "Frameworks"
    removed = 0
    if framework_dir.exists():
        for nested in sorted(framework_dir.rglob("*.bundle")):
            if not nested.is_dir():
                continue
            identity = bundle_identifier(nested)
            root = resource_bundles.get(identity)
            if root is None:
                continue

            root_files = content_hashes(root)
            nested_files = content_hashes(nested)
            if root_files != nested_files:
                differences = set(root_files.items()) ^ set(nested_files.items())
                raise SystemExit(
                    f"Refusing to remove non-identical resource bundle: {nested} "
                    f"(same Bundle ID as {root}; differing entries={len(differences)})"
                )

            print(f"Removing redundant resource bundle: {nested} (same ID as {root})")
            shutil.rmtree(nested)
            removed += 1

    print(f"Checked {app.name}; removed {removed} identical nested resource bundle(s).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path, help="Path to built iOS .app")
    args = parser.parse_args()
    deduplicate_resource_bundles(args.app)
